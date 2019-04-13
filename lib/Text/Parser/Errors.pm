package Text::Parser::Errors;
use strict;
use warnings;

use Throwable::SugarFactory;

exception 'GenericError' => 'a generic error';
exception
    'CantUndoMultiline' =>
    'the parser was originally set as a multiline parser, and that cannot be undone now',
    extends => GenericError();


1;

