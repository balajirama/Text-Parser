use strict;
use warnings;

package Text::Parser::Error;

# VERSION

# ABSTRACT: Exceptions for Text::Parser

use Moose;
use Moose::Exporter;
extends 'Throwable::Error';

Moose::Exporter->setup_import_methods( as_is => ['parser_exception'], );

=head1 DESCRIPTION

This class replaces the older C<Text::Parser::Errors> which created hundreds of subclasses. That method seemed very counter-productive and difficult to handle for programmers. There is only one function in this class that is used inside the L<Text::Parser> package. 

Any exceptions thrown by this package will be an instance of L<Text::Parser::Error>. And C<Text::Parser::Error> is a subclass of C<Throwable::Error>. So you can write your code like this:

    use Try::Tiny;

    try {
        my $parser = Text::Parser->new();
        # do something
        $parser->read();
    } catch {
        print $_->as_string, "\n" if $_->isa('Text::Parser::Error');
    };

=head1 FUNCTIONS

=func parser_exception

Accepts a single string argument and uses it as the message attribute for the exception thrown.

    parser_exception("Something bad happened") if $something_bad;

=cut

sub parser_exception {
    my $str = shift;
    $str = 'Unknown error from ' . caller() if not defined $str;
    Text::Parser::Error->throw( message => $str );
}

1;

