use strict;
use warnings;

package SpiceParser;
use parent 'Text::Parser';
use Role::Tiny::With;

with 'Text::Parser::Multiline';

use constant {
    SPICE_LINE_CONTD => qr/^[+]\s*/,
    SPICE_END_FILE   => qr/^\.end/i,
};

use Exception::Class (
    'SpiceParser::Error',
    'SpiceParser::Error::Unexpected::LineContn' => {
        isa   => 'SpiceParser::Error',
        alias => 'throw_unexpected_line_cont',
    }
);

sub multiline_type {
    return 'join_last';
}

sub join_last_line {
    my ( $self, $line ) = @_;
    my $last_line = $self->pop_joined_line;
    throw_unexpected_line_cont error =>
        'Unexpected line continuation at line #' . $self->lines_parsed()
        if not defined $last_line;
    $line =~ s/^[+]\s*//;
    chomp $last_line;
    $self->push_joined_line("$last_line $line");
}

sub is_line_part_of_last {
    my ( $self, $line ) = @_;
    return $line =~ SPICE_LINE_CONTD;
}

sub is_line_continued {
    return 0;
}

sub at_eof {
    my $self = shift;
    my $last_line = $self->pop_joined_line;
    $self->save_record($last_line) if defined $last_line;
}

sub save_record {
    my ( $self, $line ) = @_;
    return $self->abort_reading() if $line =~ SPICE_END_FILE;
    $self->SUPER::save_record($line);
}

package main;
use Test::More;
use Test::Exception;

my $sp = new SpiceParser;

lives_ok { $sp->read('t/example-2.sp'); } 'Works fine';
is( scalar( $sp->get_records() ), 1, '1 record saved' );
is( $sp->lines_parsed(),          6, '6 lines parsed' );
is( $sp->last_record, "Minst net1 net2 net3 net4 nmos l=0.09u w=0.13u\n" );

done_testing;
