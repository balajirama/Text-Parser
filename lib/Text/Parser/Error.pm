package Text::Parser::Error;
use strict;
use warnings;

# ABSTRACT: Exceptions for Text::Parser

use Moose;
use Moose::Exporter;
extends 'Throwable::Error';

=head1 DESCRIPTION

=cut

Moose::Exporter->setup_import_methods( as_is => ['parser_exception'], );

sub parser_exception {
    my $str = shift;
    $str = 'Unknown error from ' . caller() if not defined $str;
    Text::Parser::Error->throw(message => $str);
}

1;

