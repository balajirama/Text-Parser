use strict;
use warnings;

# ABSTRACT: default methods for typical mutli-line parsers

package Text::Parser::Multiline::Typical;
use Exporter 'import';
our (@EXPORT) = ();

=head1 SYNOPSIS

    package MyMultParser;
    use parent 'Text::Parser';

    use Role::Tiny::With;
    with 'Text::Parser::Multiline::Typical';
    with 'Text::Parser::Multiline';

    package main;

    my $mpars = MyMultParser->new();
    $mpars->read('file.txt');
    print "Read all ", $mpars->lines_parsed(), " lines as ", scalar($mpars->get_records()), " records\n";

=head1 DESCRIPTION

This class is a simple mutli-line parser class that can be directly inherited and composed into the L<Text::Parser::Multiline> role.

=method multiline_type

Returns C<'join_last'> string.

=cut

use Role::Tiny;

requires 'lines_parsed';

sub multiline_type {
    return 'join_last';
}

=method is_line_continued

Returns C<1> for all lines except the first line. This means all lines continue from the previous line (except the first line, because there is no line before that).

=cut

sub is_line_continued {
    my $self = shift;
    return 0 if $self->lines_parsed() == 1;
    return 1;
}

=method join_last_line

This default supplied method just appends the current line to the last line and returns the result. There is no continuation character to strip in this case. When you override this method, you might need to strip any continuation characters from the last line or the current line or both.

=cut

sub join_last_line {
    my $self = shift;
    my ( $last, $line ) = ( shift, shift );
    return $last . $line;
}

1;
