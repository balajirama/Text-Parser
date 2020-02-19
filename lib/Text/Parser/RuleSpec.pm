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
use Text::Parser::Errors;
use Text::Parser::Rule;

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
    default => sub { {} },
);

=func applies_rule

This function may be called only in a class of its own.

Takes one mandatory string argument, followed by a mandatory set of arguments that will be passed to the constructor of C<Text::Parser::Rule>.

It returns nothing, but saves a rule registered under the namespace from where this function is called.

=cut

sub applies_rule {
    my ( $meta, $name ) = ( shift, shift );
    _excepts_apply_rule( $meta, $name, @_ );
    _register_rule( _full_rule_name( $meta, $name ), @_ );
    _push_rule_order( $meta, $name );
}

sub _full_rule_name {
    my ( $meta, $name ) = ( shift, shift );
    return $meta->name . '/' . $name;
}

sub _excepts_apply_rule {
    my ( $meta, $name ) = ( shift, shift );
    die spec_must_have_name package_name => $meta->name
        if not defined $name
        or ref($name) ne '';
    die spec_requires_hash rule_name => $name if not @_ or ( scalar(@_) % 2 );
    die main_cant_apply_rule rule_name => $name if $meta->name eq 'main';
}

sub _register_rule {
    my $key = shift;
    die name_rule_uniquely if Text::Parser::RuleSpec->_exists_rule($key);
    my $rule = Text::Parser::Rule->new(@_);
    Text::Parser::RuleSpec->_add_new_rule( $key => $rule );
}

sub _push_rule_order {
    my ( $meta, $rule_name ) = ( shift, shift );
    my $h     = Text::Parser::RuleSpec->_class_rule_order;
    my $class = $meta->name;
    _init_class_rule_order( $h, $class, $meta->superclasses );
    push @{ $h->{$class} }, _full_rule_name( $meta, $rule_name );
}

sub _init_class_rule_order {
    my ( $h, $class ) = ( shift, shift );
    return if exists $h->{$class};
    $h->{$class} = [];
    $h->{$class} = exists $h->{$_} ? [ @{ $h->{$class} }, @{ $h->{$_} } ] : []
        for (@_);
}

__PACKAGE__->meta->make_immutable;

no Moose;
no MooseX::ClassAttribute;

1;
