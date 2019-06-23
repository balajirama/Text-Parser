
use strict;
use warnings;

package Text::Parser::RuleSpec;

# ABSTRACT: Rule specification for class-rules (for derived classes of Text::Parser)

=head1 SYNOPSIS

B<NOTE:> This module is still under construction. Don't use this one. Go back to using L<Text::Parser> normally.

=head1 EXPORTS

The following methods are exported into the C<use>r's namespace by default:

=for :list
* C<L<applies_rule|/applies_rule>>

=cut

use Moose;
use Moose::Exporter;
use MooseX::ClassAttribute;

Moose::Exporter->setup_import_methods(
    with_meta => ['applies_rule'],
    also      => 'Moose'
);

class_has _all_rules => (
    is      => 'rw',
    isa     => 'HashRef[Text::Parser::Rule]',
    lazy    => 1,
    default => sub { {} },
    traits  => ['Hash'],
    handles => {
        _add_new_rule => 'set',
        _exists_rule  => 'exists'
    },
);

class_has _class_rule_order => (
    is      => 'rw',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    default => sub {
        { [] }
    },
);

=func applies_rule

Takes one mandatory string argument, followed by a mandatory set of arguments that will be passed to the constructor of C<Text::Parser::Rule>.

It returns nothing, but saves a rule registered under the namespace from where this function is called.

=cut

sub applies_rule {
    my ( $meta, $name ) = ( shift, shift );
    return if not defined $name or defined ref($name);
    my $rule = Text::Parser::Rule->new(@_);
    Text::Parser::RuleSpec->_add_new_rule( $meta->name . '/' . $name, $rule );
}

__PACKAGE__->meta->make_immutable;

no Moose;
no MooseX::ClassAttribute;

1;
