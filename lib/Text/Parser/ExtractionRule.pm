use strict;
use warnings;

package Text::Parser::ExtractionRule;

# ABSTRACT: Record extraction rules

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = (@EXPORT_OK);

use Moose::Util::TypeConstraints;

subtype StrNoSpace => (
    as      => 'Str',
    where   => { $_ !~ /\s+/ },
    message => "\'$_\' has spaces",
);

no Moose::Util::TypeConstraints;

use Moose;

has condition => (
    is       => 'rw',
    isa      => 'Str',
    trigger  => \&_convert_to_sub,
    required => 1,
);

has _cond_sub => (
    is  => 'ro',
    isa => 'CodeRef',
);

has action => (
    is       => 'rw',
    isa      => 'CodeRef',
    required => 1,
);

__PACKAGE__->meta->make_immutable;

no Moose;

1;
