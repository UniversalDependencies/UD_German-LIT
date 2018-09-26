#!/usr/bin/env perl
# Merges the original text file of German fragments with the CoNLL-U annotation.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $srcfilename = 'ud_ger_frag_temp_raw.txt';
my $conllufilename = 'ud_ger_frag_gold_temp.conllu.txt';
# Read the entire source file into memory. With 251 kB, it should not be a problem.
open(SRC, $srcfilename) or die("Cannot read $srcfilename: $!");
while(<SRC>)
{
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
            'text'   => $current_fragment
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
print("Found $n fragments in total.\n");
# Read the CoNLL-U file into memory.
open(CONLLU, $conllufilename) or die("Cannot read $conllufilename: $!");
my @conllu = ();
my @current_sentence = ();
while(<CONLLU>)
{
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
print("Found $o sentences in the CoNLL-U file.\n");
# Synchronize the CoNLL-U sentences with the raw fragments.
# According to Alessio, some sentences may be omitted in the CoNLL-U file.
# However, all CoNLL-U sentences can be located somewhere in the raw fragments.
my $ifrg = 0;
my $isnt = 0;
while($isnt <= $#conllu)
{
    # Get the non-whitespace string of the sentence.
    my $nwhsp = '';
    foreach my $line (@{$conllu[$isnt]})
    {
        if($line =~ m/^\d+\t/)
        {
            my @f = split(/\t/, $line);
            # For some reason, semicolons are enclosed in quotation marks in the CoNLL-U file, although they were not in original.
            $f[1] = ';' if($f[1] eq '";"');
            $nwhsp .= $f[1];
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
        print STDERR ("Sentence $isnt matches fragment $ifrg.\n");
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
            print STDERR ("Sentence $isnt is a prefix of fragment $ifrg.\n");
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
            print STDERR ("Sentence $isnt found in fragment $ifrg. Discarding unmatched prefix of the fragment.\n");
        }
        # The current fragment does not contain the current sentence.
        # Proceed to the next fragment.
        else
        {
            print STDERR ("Sentence $isnt not found in fragment $ifrg.\n");
            $ifrg++;
            # If there are no more fragments, something went wrong because we were supposed to find all sentences and we didn't.
            if($ifrg > $#fragments)
            {
                print STDERR ("Something went wrong and we did not find the sentence $isnt:\n");
                print STDERR ("  '$nwhsp'\n");
                print STDERR ("Last sentence found:\n");
                print STDERR ("  '$last_sentence_found'\n");
                die();
            }
        }
    }
    # Fragment is shorter than sentence. Proceed to the next fragment.
    else
    {
        print STDERR ("Sentence $isnt is longer than the remainder of fragment $ifrg.\n");
        $ifrg++;
        # If there are no more fragments, something went wrong because we were supposed to find all sentences and we didn't.
        if($ifrg > $#fragments)
        {
            print STDERR ("Something went wrong and we did not find the sentence $isnt:\n");
            print STDERR ("  '$nwhsp'\n");
            print STDERR ("Last sentence found:\n");
            print STDERR ("  '$last_sentence_found'\n");
            die();
        }
    }
}
