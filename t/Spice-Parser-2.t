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

sub multiline_type {
    return 'join_last';
}

sub strip_continuation_char {
    my ( $self, $line ) = (shift, shift);
    return undef if not defined $line;
    $line =~ s/^[+]\s*/ /;
    return $line;
}

sub is_line_part_of_last {
    my ( $self, $line ) = @_;
    return 0 if not defined $line;
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

sub new {
    my $pkg = shift;
    $pkg->SUPER::new(auto_chomp => 1);
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
isa_ok($sp, 'SpiceParser');
isa_ok($sp, 'Text::Parser');

lives_ok { $sp->read('t/example-2.sp'); } 'Works fine';
is( scalar( $sp->get_records() ), 1, '1 record saved' );
is( $sp->lines_parsed(),          6, '6 lines parsed' );
is( $sp->last_record, "Minst net1 net2 net3 net4 nmos l=0.09u w=0.13u" );

done_testing;
