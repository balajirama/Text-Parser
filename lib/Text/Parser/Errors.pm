package Text::Parser::Errors;
use strict;
use warnings;

use Throwable::SugarFactory;
use Scalar::Util 'looks_like_number';

# ABSTRACT: Exceptions for Text::Parser

=head1 DESCRIPTION

This document contains a manifest of all the exception classes thrown by L<Text::Parser>.

=head1 EXCEPTION CLASSES

All exceptions are derived from C<Text::Parser::Errors::GenericError>. They are all based on L<Throwable::SugarFactory> and so all the exception methods of those, such as C<L<error|Throwable::SugarFactory/error>>, C<L<namespace|Throwable::SugarFactory/namespace>>, etc., will be accessible. Read L<Exceptions> if you don't know about exceptions in Perl 5.

=cut

sub _Str {
    die "attribute must be a string"
        if not defined $_[0]
        or ref( $_[0] ) ne '';
}

sub _Num {
    die "attribute must be a number"
        if not defined $_[0]
        or not looks_like_number( $_[0] );
}

exception 'GenericError' => 'a generic error';

=head2 Input file related errors

=head3 C<Text::Parser::Errors::InvalidFilename>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> is invalid.

=head4 Attributes

=for :list
* B<name> - a string with the anticipated file name.

=cut

exception
    InvalidFilename => 'file does not exist',
    has             => [
    name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::FileNotReadable>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> has no read permissions or is unreadable for any other reason.

=head4 Attributes

=for :list
* B<name> - a string with the name of the file that could not be read

=cut

exception
    FileNotReadable => 'file does not exist',
    has             => [
    name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => GenericError();

=head2 Errors in C<multiline_type> parsers

=head3 C<Text::Parser::Errors::CantUndoMultiline>

Thrown when C<multiline_type> is being set to C<undef> back from another valid value.

=cut

exception
    'CantUndoMultiline' => 'already multiline parser, cannot be undone',
    extends             => GenericError();

=head3 C<Text::Parser::Errors::UnexpectedEof>

Thrown only for C<join_next> multiline parsers (supporting line-wrap), when a line continuation character indicates that the last line in the file is wrapped on to the next line.

=head4 Attributes

=for :list
* B<discontd> - a string containing the line with the continuation character.
* B<line_num> - line number at which the unexpected EOF is encountered.

=cut

exception
    UnexpectedEof => 'join_next cont. character in last line, unexpected EoF',
    has           => [
    discontd => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    has => [
    line_num => (
        is  => 'ro',
        isa => \&_Num,
    ),
    ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::UnexpectedCont>

Thrown only for C<join_last> multiline parsers (supporting line-wrap), when a line continuation character at the beginning of a file, indicates that it is a continuation of the previous line (there is no line before the first line).

=head4 Attributes

=for :list
* B<line> - a string containing the content of the line with the unexpected continuation character.

=cut

exception
    UnexpectedCont => 'join_last cont. character on first line',
    has            => [
    line => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => GenericError();

=head1 SEE ALSO

=for :list
* L<Text::Parser>
* L<Throwable::SugarFactory>
* L<Exceptions>

=cut

1;

