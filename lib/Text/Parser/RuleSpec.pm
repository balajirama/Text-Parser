use strict;
use warnings;

package Text::Parser::RuleSpec;

# ABSTRACT: Syntax sugar for rule specification while subclassing Text::Parser or derivatives

=head1 SYNOPSIS

    package MyParser;

    use Text::Parser::RuleSpec;
    extends 'Text::Parser';

    has '+line_wrap_style' => (default => 'custom');
    has '+multiline_type'  => (default => 'join_next');

    unwraps_lines_using (
        is_wrapped     => sub {
            my $self = shift;
            $_ = shift;
            chomp;
            m/\s+[~]\s*$/;
        }, 
        unwrap_routine => sub {
            my ($self, $last, $current) = @_;
            chomp $last;
            $last =~ s/\s+[~]\s*$//g;
            "$last $current";
        }, 
    );

    applies_rule get_emails => (
        if => '$1 eq "EMAIL:"', 
        do => '$2;'
    );

    package main;

    my $parser = MyParser->new();
    $parser->read('/path/to/email_lists.txt');
    my (@emails) = $parser->get_records();
    print "Here are all the emails from the file: @emails\n";

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
    with_meta => [ 'applies_rule', 'unwraps_lines_using' ],
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
        _exists_rule  => 'exists',
        _get_rule     => 'get',
    },
);

class_has _class_rule_order => (
    is      => 'rw',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    default => sub { {} },
);

=func applies_rule

May be called only outside the C<main> namespace. Takes one mandatory string argument which is a rule name, followed by the options to create a rule. These are the same as the arguments to the C<L<add_rule|Text::Parser/"add_rule">> method. Returns nothing. Exceptions will be thrown if any of the required arguments are not provided.

    applies_rule print_emails => (
        if               => '$1 eq "EMAIL:"', 
        do               => 'print $2;', 
        dont_record      => 1, 
        continue_to_next => 1, 
    );

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

=func unwraps_lines_using

=cut

sub unwraps_lines_using {
    my $meta = shift;
    my ( $is_wr, $unwr ) = _check_custom_unwrap_args(@_);
    _set_default_of_attribute( $meta, line_wrap_style => 'custom' );
    _set_default_of_attribute( $meta, _is_wrapped     => sub { $is_wr; } );
    _set_default_of_attribute( $meta, _unwrap_routine => sub { $unwr; } );
}

sub _check_custom_unwrap_args {
    die bad_custom_unwrap_call( err => 'Need 4 arguments' )
        if @_ != 4;
    _test_fields_unwrap_rtn(@_);
    my (%opt) = (@_);
    return ( $opt{is_wrapped}, $opt{unwrap_routine} );
}

sub _test_fields_unwrap_rtn {
    my (%opt) = (@_);
    die bad_custom_unwrap_call(
        err => 'must have keys: is_wrapped, unwrap_routine' )
        if not( exists $opt{is_wrapped} and exists $opt{unwrap_routine} );
    _is_arg_a_code( $_, %opt ) for (qw(is_wrapped unwrap_routine));
}

sub _is_arg_a_code {
    my ( $arg, %opt ) = (@_);
    die bad_custom_unwrap_call( err => "$arg key must reference code" )
        if 'CODE' ne ref( $opt{$arg} );
}

sub _set_default_of_attribute {
    my ( $meta, %val ) = @_;
    foreach my $k ( keys %val ) {
        my $old = $meta->find_attribute_by_name($k);
        my $new = $old->clone_and_inherit_options( default => $val{$k} );
        $meta->add_attribute($new);
    }
}

__PACKAGE__->meta->make_immutable;

no Moose;
no MooseX::ClassAttribute;

1;
