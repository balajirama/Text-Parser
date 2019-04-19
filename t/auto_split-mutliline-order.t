
use strict;
use warnings;

package MyTestParser;
use Test::More;    # last test to print
use Moose;
extends 'Text::Parser';

sub save_record {
    my $self   = shift;
    my $nf     = scalar( split /\s+/, $_[0] );
    my $status = ( not $nf or $nf > 15 ) ? 1 : 0;
    ok( $status, 'Joined lines properly' );
    $self->SUPER::save_record(@_) if $nf;
}

my $pattern = '\$\s*';

override is_line_continued => sub {
    my $self = shift;
    ok $self->field(-1) =~ /$pattern/, $self->this_line . " is continued"
        if $self->this_line =~ /$pattern/;
    $self->this_line =~ /$pattern/;
};

override join_last_line => sub {
    my $self = shift;
    my ( $last, $line ) = @_;
    $last =~ s/$pattern//g;
    return $last . ' ' . $line;
};

sub BUILDARGS {
    return { auto_chomp => 1 };
}

package main;
use Test::More;

my @parser;
$parser[0] = MyTestParser->new();
isa_ok $parser[0], 'Text::Parser';
lives_ok {
    $parser[0]->auto_split(1);
    $parser[0]->multiline_type('join_next');
    $parser[0]->read('t/example-wrapped.txt');
    is scalar( $parser[0]->get_records ), 2, 'Exactly 2 lines';
}
'Set up the attributes without dying';

$parser[1] = MyTestParser->new();
isa_ok $parser[1], 'Text::Parser';
lives_ok {
    $parser[1]->multiline_type('join_next');
    $parser[1]->auto_split(1);
    $parser[1]->read('t/example-wrapped.txt');
    is scalar( $parser[1]->get_records ), 2, 'Exactly 2 lines';
}
'Set up the attributes without dying';

done_testing;
