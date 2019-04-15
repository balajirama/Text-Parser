package Text::Parser::Errors;
use strict;
use warnings;

use Throwable::SugarFactory;
use Scalar::Util 'looks_like_number';

# ABSTRACT: Exceptions for Text::Parser

=head1 DESCRIPTION

This document contains a manifest of all the exception classes thrown by L<Text::Parser>.

=head1 EXCEPTION CLASSES

All exceptions are derived from C<Text::Parser::Errors::GenericError>. They are all based on L<Throwable::SugarFactory> and so all the exception methods of those, such as C<L<error|Throwable::SugarFactory/error>>, C<L<namespace|/Throwable::SugarFactory/namespace>>, etc., will be accessible. Read L<Exceptions> if you don't know about exceptions in Perl 5.

=cut

exception 'GenericError' => 'a generic error';

=head2 C<Text::Parser::Errors::InvalidFilename>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> is invalid.

=head3 Attributes

=head4 name

A string with the anticipated file name.

=cut

exception
    InvalidFilename => 'file does not exist',
    has           => [
    name => (
        is  => 'ro',
        isa => sub {
            die "$_[0] must be a string" if '' ne ref( $_[0] );
        }
    )
    ],
    extends => GenericError();

=head2 C<Text::Parser::Errors::InvalidFilename>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> has no read permissions or is unreadable for any other reason.

=head3 Attributes

=head4 name

A string with the name of the file that could not be read

=cut

exception
    FileNotReadable => 'file does not exist',
    has           => [
    name => (
        is  => 'ro',
        isa => sub {
            die "$_[0] must be a string" if '' ne ref( $_[0] );
        }
    )
    ],
    extends => GenericError();

=head2 C<Text::Parser::Errors::CantUndoMultiline>

Thrown when a multi-line parser is turned back to a non-multiline one.

=cut

exception
    'CantUndoMultiline' => 'already multiline parser, cannot be undone',
    extends             => GenericError();

=head2 C<Text::Parser::Errors::UnexpectedEof>

Thrown when a line continuation character is at the end of a file, indicating that the line is continued on the next line. Since there is no further line, the line continuation is left unterminated and is an error condition. This exception is thrown only for C<join_next> type of multiline parsers.

=head3 Attributes

=head4 discontd

This is a string containing the line which got discontinued by the unexpected EOF.

=head4 line_num

The line at which the unexpected EOF is encountered.

=cut
    
exception
    UnexpectedEof => 'continuation character in last line, unexpected EoF',
    has           => [
    discontd => (
        is  => 'ro',
        isa => sub {
            die "$_[0] must be a string" if '' ne ref( $_[0] );
        }
    )
    ],
    has => [
    line_num => (
        is  => 'ro',
        isa => sub {
            die "$_[0] must be a number"
                if ref( $_[0] ) ne ''
                or not looks_like_number( $_[0] );
        }
    )
    ],
    extends => GenericError();

=head2 C<Text::Parser::Errors::UnexpectedCont>

Thrown when a line continuation character is at the beginning of a file, indicating that the previous line should be joined. Since there is no line before the first line, this is an error condition. This is thrown only in C<join_last> type of multiline parsers.

=head3 Attributes

=head4 line

This is a string containing the content of the line with the unexpected continuation character. Given the description, it is obvious that the line number is C<1>.

=cut

exception
    UnexpectedCont => 'join_last cont. character on first line',
    has            => [
    line => (
        is  => 'ro',
        isa => sub {
            die "$_[0] must be a string" if '' ne ref( $_[0] );
        },
    )
    ],
    extends => GenericError();


=head1 SEE ALSO

=for :list
* L<Text::Parser>
* L<Throwable::SugarFactory>
* L<Exceptions>

=cut

1;

