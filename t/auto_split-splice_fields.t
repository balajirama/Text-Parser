
use strict;
use warnings;

package MyTestParser;
use Test::More;    # last test to print
use Moose;
extends 'Text::Parser';

sub save_record {
    my $self = shift;
    return if $self->NF == 0;
    my $old = $self->field(0);
    my $nf  = $self->NF;
    my (@last) = $self->field_range( -2, -1 ) if $self->NF >= 2;
    is $nf, $self->NF, 'NF is still intact';
    is( $last[0],
        $self->field( $self->NF - 2 ),
        "$last[0] is the penultimate"
    );
    is( $last[1], $self->field( $self->NF - 1 ), "$last[1] is the last" );
    my (@flds) = $self->splice_fields( 1, $self->NF - 1 );
    is $self->NF, 1, 'Only one field left now';
    is $old, $self->field(0),
        'The field function still returns the same string';
    $self->SUPER::save_record(@_);
}

sub BUILDARGS {
    return { auto_chomp => 1, auto_split => 1 };
}

package main;

use Test::More;    # last test to print

my $p = MyTestParser->new();
$p->read('t/example-split.txt');

done_testing;
