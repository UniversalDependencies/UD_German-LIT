#!/usr/bin/env perl
# Merges the original text file of German fragments with the CoNLL-U annotation.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Lingua::Interset::Converter;

my $c = new Lingua::Interset::Converter ('from' => 'de::stts', 'to' => 'mul::upos');
my $srcfilename = 'ud_ger_frag_temp_raw.txt';
my $conllufilename = 'ud_ger_frag_gold_temp.conllu.txt';
# Read the entire source file into memory. With 251 kB, it should not be a problem.
@fragments = read_fragments($srcfilename);
# Read the CoNLL-U file into memory.
open(CONLLU, $conllufilename) or die("Cannot read $conllufilename: $!");
my @conllu = ();
my @current_sentence = ();
$il = 0;
while(<CONLLU>)
{
    $il++;
    if(scalar(@current_sentence)==0)
    {
        push(@sentence_start_line_numbers, $il);
    }
    ###!!! Test: skip multi-word-token lines.
    next if(m/^\d+-\d+/);
    # Remove sentence-terminating characters.
    s/\r?\n$//;
    push(@current_sentence, $_);
    # An empty line terminates a sentence.
    if(m/^\s*$/)
    {
        my @sentence = @current_sentence;
        push(@conllu, \@sentence);
        @current_sentence = ();
    }
}
close(CONLLU);
my $o = scalar(@conllu);
print STDERR ("Found $o sentences in the CoNLL-U file.\n");
do
{
    print STDERR ("Synchronization starts...\n");
    my $dying = 0;
    my $restart = 0;
    # Synchronize the CoNLL-U sentences with the raw fragments.
    # According to Alessio, some sentences may be omitted in the CoNLL-U file.
    # However, all CoNLL-U sentences can be located somewhere in the raw fragments.
    my $ifrg = 0;
    my $isnt = 0;
    # Remember if the last message was "not found". Avoid displaying too many such messages.
    my $lmnf = 0;
    while($isnt <= $#conllu)
    {
        # Get the non-whitespace string of the sentence.
        my $nwhsp = '';
        my $from;
        my $to;
        foreach my $line (@{$conllu[$isnt]})
        {
            # Process multi-word tokens.
            if($line =~ m/^(\d+)-(\d+)\t/)
            {
                $from = $1;
                $to = $2;
                my @f = split(/\t/, $line);
                $nwhsp .= $f[1];
            }
            if($line =~ m/^(\d+)\t/)
            {
                my $id = $1;
                if(defined($to) && $id > $to)
                {
                    $from = undef;
                    $to = undef;
                }
                unless(defined($to))
                {
                    my @f = split(/\t/, $line);
                    # For some reason, semicolons are enclosed in quotation marks in the CoNLL-U file, although they were not in original.
                    $f[1] = ';' if($f[1] eq '";"');
                    $nwhsp .= $f[1];
                }
            }
        }
        $nwhsp =~ s/\s//g;
        # Look at the beginning of the current fragment. Is the sentence there?
        my $frgnwhsp = $fragments[$ifrg]{text};
        $frgnwhsp =~ s/\s//g;
        # Occasionally the CoNLL-U file does not keep the original casing, so we should compare the characters case-insensitively.
        $nwhsp = lc($nwhsp);
        $frgnwhsp = lc($frgnwhsp);
        # The easiest case: the current fragment consists just of the current sentence.
        if($nwhsp eq $frgnwhsp)
        {
            $metasnt[$isnt]{ifrg} = $ifrg;
            $last_sentence_found = $metasnt[$isnt]{text} = $fragments[$ifrg]{text};
            print STDERR ("Sentence $isnt (line $sentence_start_line_numbers[$isnt]) matches fragment $ifrg (line $fragments[$ifrg]{line}).\n");
            $lmnf = 0;
            # Proceed to the next CoNLL-U sentence and the next fragment.
            $isnt++;
            $ifrg++;
        }
        elsif(length($nwhsp) <= length($frgnwhsp))
        {
            if(substr($frgnwhsp, 0, length($nwhsp)) eq $nwhsp)
            {
                # The current fragment begins with the current sentence.
                # But we do not know how many extra whitespace characters there are.
                my @frgchars = split(//, $fragments[$ifrg]{text});
                my @sntchars = split(//, $nwhsp);
                my $sentence = '';
                while(scalar(@sntchars) > 0)
                {
                    if(lc($frgchars[0]) eq lc($sntchars[0]))
                    {
                        $sentence .= shift(@frgchars);
                        shift(@sntchars);
                    }
                    elsif($frgchars[0] =~ m/\s/)
                    {
                        $sentence .= shift(@frgchars);
                    }
                    else
                    {
                        print STDERR ("Something is wrong!\n");
                        print STDERR ("  Fragment remainder = '", join('', @frgchars), "'\n");
                        print STDERR ("  Sentence remainder = '", join('', @sntchars), "'\n");
                        die();
                    }
                }
                $metasnt[$isnt]{ifrg} = $ifrg;
                $last_sentence_found = $metasnt[$isnt]{text} = $sentence;
                # Remove the sentence from the current fragment.
                while(length(@frgchars) > 0 && $frgchars[0] =~ m/\s/)
                {
                    shift(@frgchars);
                }
                $fragments[$ifrg]{text} = join('', @frgchars);
                print STDERR ("Sentence $isnt (line $sentence_start_line_numbers[$isnt]) is a prefix of fragment $ifrg (line $fragments[$ifrg]{line}).\n");
                $lmnf = 0;
                # Proceed to the next CoNLL-U sentence.
                $isnt++;
            }
            # The current fragment does not begin with the current sentence.
            # Does it at least contain the current sentence?
            elsif($frgnwhsp =~ s/^(.*?)(\Q$nwhsp\E.*)$/$2/)
            {
                # Discard the unrecognized initial part of the fragment (including whitespace).
                my @dischars = split(//, $1);
                my @frgchars = split(//, $fragments[$ifrg]{text});
                while(scalar(@dischars) > 0)
                {
                    if(lc($frgchars[0]) eq lc($dischars[0]))
                    {
                        shift(@frgchars);
                        shift(@dischars);
                    }
                    elsif($frgchars[0] =~ m/\s/)
                    {
                        shift(@frgchars);
                    }
                    else
                    {
                        print STDERR ("Something is wrong!\n");
                        print STDERR ("  Fragment remainder = '", join('', @frgchars), "'\n");
                        print STDERR ("  Discard remainder  = '", join('', @dischars), "'\n");
                        die();
                    }
                }
                while(scalar(@frgchars) > 0 && $frgchars[0] =~ m/\s/)
                {
                    shift(@frgchars);
                }
                $fragments[$ifrg]{text} = join('', @frgchars);
                # Now the fragment begins with the current sentence and the next pass through the loop will match them.
                print STDERR ("Sentence $isnt (line $sentence_start_line_numbers[$isnt]) found in fragment $ifrg. Discarding unmatched prefix of the fragment.\n");
                $lmnf = 0;
            }
            # The current fragment does not contain the current sentence.
            # Proceed to the next fragment.
            else
            {
                print STDERR ("Sentence $isnt (line $sentence_start_line_numbers[$isnt]) not found in fragment $ifrg (line $fragments[$ifrg]{line}).\n") unless($lmnf);
                $lmnf = 1;
                $ifrg++;
                # If there are no more fragments, something went wrong because we were supposed to find all sentences and we didn't.
                if($ifrg > $#fragments)
                {
                    print STDERR ("Something went wrong and we did not find the sentence $isnt (line $sentence_start_line_numbers[$isnt]):\n");
                    print STDERR ("  '$nwhsp'\n");
                    print STDERR ("Last sentence found:\n");
                    print STDERR ("  '$last_sentence_found'\n");
                    $dying = 1;
                }
            }
        }
        # Fragment is shorter than sentence. Proceed to the next fragment.
        else
        {
            print STDERR ("Sentence $isnt (line $sentence_start_line_numbers[$isnt]) is longer than the remainder of fragment $ifrg (line $fragments[$ifrg]{line}).\n") unless($lmnf);
            $lmnf = 1;
            $ifrg++;
            # If there are no more fragments, something went wrong because we were supposed to find all sentences and we didn't.
            if($ifrg > $#fragments)
            {
                print STDERR ("Something went wrong and we did not find the sentence $isnt (line $sentence_start_line_numbers[$isnt]):\n");
                print STDERR ("  '$nwhsp'\n");
                print STDERR ("Last sentence found:\n");
                print STDERR ("  '$last_sentence_found'\n");
                $dying = 1;
            }
        }
        if($dying)
        {
            $restart = add_mwt($conllu[$isnt]);
            if($restart)
            {
                print STDERR ("Added a multi-word token and re-trying from scratch.\n");
                splice(@metasnt);
                # Re-read the fragments because we have been processing them destructively.
                @fragments = read_fragments($srcfilename);
                last;
            }
            else
            {
                die;
            }
        }
    }
}
while($restart);
# All sentences have been matched against the original text. Enrich the CoNLL-U representation with metadata.
# Friedrich Schlegel: Lyceum Fragmente
# Novalis: Blüthenstaub
# Friedrich Schlegel: Athenäums Fragmente
my %docid =
(
    'Lyceum Fragmente'    => 'lyceum',
    'Blüthenstaub'        => 'bluethenstaub',
    'Athenäums Fragmente' => 'athenaeum'
);
my $is;
for(my $i = 0; $i <= $#conllu; $i++)
{
    my $fragment = $fragments[$metasnt[$i]{ifrg}];
    my $lfragment = $i==0 ? {} : $fragments[$metasnt[$i-1]{ifrg}];
    my $did = $docid{$fragment->{work}};
    if(!defined($did))
    {
        $did = $fragment->{work};
        $did =~ s/\s//g;
    }
    if($i == 0 || $fragment->{work} ne $lfragment->{work})
    {
        print("# newdoc id = $did\n");
    }
    my $fid = "$did-f$fragment->{fid}";
    if($i == 0 || $fragment->{fid} != $lfragment->{fid})
    {
        print("# newpar id = $fid\n");
        $is = 1;
    }
    else
    {
        $is++;
    }
    my $sid = "$fid-s$is";
    print("# author = $fragment->{author}\n");
    print("# work = $fragment->{work}\n");
    print("# sent_id = $sid\n");
    my $text = $metasnt[$i]{text};
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    print("# text = $text\n");
    my $from;
    my $to;
    foreach my $line (@{$conllu[$i]})
    {
        if($line =~ m/^(\d+)-(\d+)\t/)
        {
            $from = $1;
            $to = $2;
            my @f = split(/\t/, $line);
            # Make sure that the casing of the word form matches the original text.
            my $l = length($f[1]);
            $text =~ s/^(.{$l})//;
            $f[1] = $1;
            unless($text eq '' || $text =~ s/^\s+//)
            {
                $f[9] = 'SpaceAfter=No';
            }
            $line = join("\t", @f);
        }
        if($line =~ m/^(\d+)\t/)
        {
            my $id = $1;
            if(defined($to) && $id > $to)
            {
                $from = undef;
                $to = undef;
            }
            my @f = split(/\t/, $line);
            unless(defined($to))
            {
                # Fix the quoted semicolons.
                $f[1] = ';' if($f[1] eq '";"');
                # Make sure that the casing of the word form matches the original text.
                my $l = length($f[1]);
                $text =~ s/^(.{$l})//;
                my $original = $1;
                ###!!! Warning! Occasionally the annotated text lacks an original space and we will fall out of sync if we copy it!
                ###!!! We thus check whether the only difference is casing; if not, we will not replace the form, we will leave the
                ###!!! CoNLL-U file invalid and the annotation will have to be fixed manually.
                if(lc($original) eq lc($f[1]))
                {
                    $f[1] = $1;
                }
                unless($text eq '' || $text =~ s/^\s+//)
                {
                    $f[9] = 'SpaceAfter=No';
                }
            }
            # The tags that are now in the data should be in XPOS.
            # We also need to generate UPOS from them!
            $f[4] = $f[3];
            $f[3] = $c->convert($f[4]);
            $line = join("\t", @f);
        }
        print("$line\n");
    }
}



#------------------------------------------------------------------------------
# Tries to add missing multi-word-token lines. There is no 100% rule for adding
# them so this code should only be invoked when a CoNLL-U sentence cannot be
# found in the source text.
#------------------------------------------------------------------------------
sub add_mwt
{
    my $sentence = shift;
    my $changed_something = 0;
    # It is possible that the input CoNLL-U file is missing multi-word-token lines.
    # Alessio's annotation tool does not support them.
    # We will now rely on a fixed list of preposition-article contractions and add the lines.
    for(my $i = 1; $i <= $#{$sentence}; $i++)
    {
        if($sentence->[$i] =~ m/^\d+\t/ && $sentence->[$i-1] =~ m/^\d+\t/)
        {
            my @fc = split(/\t/, $sentence->[$i]);
            my @fp = split(/\t/, $sentence->[$i-1]);
            # Warning! The putative article could also be a pronoun, as in "In dem, was man Philosophie nennt..." Then it should not be contracted!
            # More warning!!! It turns out that these text can contain uncontracted preposition+article! Quite a few occurrences like "in dem Kontrast".
            # So we must not assume contraction if we can synchronize without it.
            if(#$fc[3] !~ m/^(PDS|PRELS)$/ &&
               (lc($fc[1]) eq 'dem' && lc($fp[1]) =~ m/^(in|zu|an|von)$/ ||
                lc($fc[1]) eq 'der' && lc($fp[1]) =~ m/^(zu)$/ ||
                lc($fc[1]) eq 'das' && lc($fp[1]) =~ m/^(in)$/))
            {
                if($i<2 || $sentence->[$i-2] !~ m/^\d+-\d+\t/)
                {
                    my @fmwt = ("$fp[0]-$fc[0]", '_', '_', '_', '_', '_', '_', '_', '_', '_');
                    $fmwt[1] = $fp[1];
                    my $suffix = substr($fc[1], 2, 1); # could be uppercase
                    if($fmwt[1] =~ m/^zu$/i || $fc[1] =~ m/^(der|das)$/i)
                    {
                        $fmwt[1] .= $suffix;
                    }
                    else # im am vom
                    {
                        $fmwt[1] =~ s/n$/$suffix/i;
                    }
                    my $fmwt = join("\t", @fmwt);
                    splice(@{$sentence}, $i-1, 0, $fmwt);
                    $changed_something = 1;
                    $i++;
                }
            }
        }
    }
    return $changed_something;
}



#------------------------------------------------------------------------------
# Reads the entire source file into memory. With 251 kB, it should not be
# a problem.
#------------------------------------------------------------------------------
sub read_fragments
{
    my $srcfilename = shift;
    my $current_author;
    my $current_work;
    my $current_fragment_number;
    my $current_fragment;
    my @fragments;
    open(SRC, $srcfilename) or die("Cannot read $srcfilename: $!");
    my $il = 0;
    while(<SRC>)
    {
        $il++;
        # Skip empty lines. They do not seem to be significant.
        next if(m/^\s*$/);
        # Remove the line terminating characters, and any leading or trailing spaces.
        s/\r?\n$//;
        s/\s+$//;
        s/^\s+//;
        # Comment lines introduce a new document.
        if(m/^\#\s*Author:\s*(.+)/i)
        {
            $current_author = $1;
        }
        elsif(m/^\#\s*Work:\s*(.+)/i)
        {
            $current_work = $1;
        }
        elsif(m/^\#/)
        {
            die("Cannot understand line:\n$_\n");
        }
        # In some works, the fragment numbers are formatted like [1].
        # In others, the numbers are formatted like 1.
        # Fragment numbers are unique within one work.
        elsif(s/^\[(\d+)\]\s*// || s/(\d+)\.\s*//)
        {
            $current_fragment_number = $1;
            # The fragment text consists of one or more sentences.
            $current_fragment = $_;
            my %record =
            (
                'author' => $current_author,
                'work'   => $current_work,
                'fid'    => $current_fragment_number,
                'text'   => $current_fragment,
                'line'   => $il
            );
            push(@fragments, \%record);
        }
        # Sometimes a line of text does not start with the number of the fragment.
        # Treat it as a part of the previous fragment.
        else
        {
            $fragments[-1]{text} .= " $_";
        }
    }
    close(SRC);
    # Sometimes the text of the fragment contains references (number in square brackets)
    # to other fragments. They are not part of the annotated text and we have to discard
    # them.
    foreach my $fragment (@fragments)
    {
        $fragment->{text} =~ s/\[\d+\]//g;
    }
    my $n = scalar(@fragments);
    print STDERR ("Found $n fragments in total.\n");
    return @fragments;
}
