
use strict;
use warnings;

package MultLineParser;
use parent 'Text::Parser';

use Role::Tiny::With;
with 'Text::Parser::Multiline::Typical';
with 'Text::Parser::Multiline';

sub join_last_line {
    my ( $self, $last, $line ) = ( shift, shift, shift );
    return $line if not defined $last;
    chomp $last;
    $last =~ s/\\\s*$/ /g;
    return $last . $line;
}

sub is_line_continued {
    my ( $self, $line ) = ( shift, shift );
    chomp $line;
    return 1 if $line =~ /\\\s*$/;
    return 0;
}

sub multiline_type {
    return 'join_next';
}

package main;
use Test::More;
use Test::Exception;

my $mpars;
lives_ok {
    $mpars = MultLineParser->new();
    $mpars->read('t/continued.txt');
}
'The code reads without errors';

is_deeply(
    [ $mpars->get_records() ],
    [   "Some text on this line is being continued on the next  line with the back-slash character. This is more readable  than having the whole text on one single line.\n"
    ],
    'Matches the input exactly'
);

throws_ok {
    $mpars->read('t/bad-continued.txt');
} 'Text::Parser::Multiline::Error', '';

done_testing;
