
use strict;
use warnings;

package Text::Parser::ExAWK;

# ABSTRACT: Package of subroutines to intuitively create/manage ExAWK rules

use Moose;
use MooseX::ClassAttribute;
use Moose::Exporter;

Moose::Exporter->setup_import_methods(
    as_is => ['rule'],
    also  => 'Moose',
);

class_has _global_rules => (
    is      => 'rw',
    isa     => 'HashRef[Text::Parser::ExAWK::Rule]',
    default => sub { {} },
    traits  => ['Hash'],
);

class_has _class_rule_order => (
    is      => 'rw',
    isa     => 'HashRef[ArrayRef[Str]]',
    default => sub { {} },
    traits  => ['Hash'],
);

sub rule {
    return;
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;
