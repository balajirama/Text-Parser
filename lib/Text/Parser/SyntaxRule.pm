use strict;
use warnings;

package Text::Parser::SyntaxRule;

# ABSTRACT: Record extraction rules

use Moose;

has condition => (
    is       => 'rw',
    isa      => 'Str|CodeRef',
    required => 1,
);

has _cond_sub => (
    is  => 'ro',
    isa => 'CodeRef',
    init_arg => undef, 
);

has action => (
    is       => 'rw',
    isa      => 'Str|CodeRef',
);

has _act_sub => (
    is  => 'ro',
    isa => 'CodeRef',
    init_arg => undef, 
);

sub BUILD {
    my $self = shift;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

