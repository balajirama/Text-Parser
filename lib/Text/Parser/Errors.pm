package Text::Parser::Errors;
use strict;
use warnings;

use Throwable::SugarFactory;
use Scalar::Util 'looks_like_number';

exception 'GenericError' => 'a generic error';
exception
    'CantUndoMultiline' => 'already multiline parser, cannot be undone',
    extends             => GenericError();
exception
    UnexpectedEof => 'continuation character in last line, unexpected EoF',
    has           => [
    remaining => (
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

1;

