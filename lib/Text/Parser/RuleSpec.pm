use strict;
use warnings;

package Text::Parser::RuleSpec;

# ABSTRACT: Syntax sugar for rule specification while subclassing Text::Parser or derivatives

=head1 SYNOPSIS

    package MyParser;

    use Text::Parser::RuleSpec;
    extends 'Text::Parser';

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

=head1 METHODS

All methods can be called directly on the C<Text::Parser::RuleSpec> class directly.

=cut

use Moose;
use Moose::Exporter;
use MooseX::ClassAttribute;
use Text::Parser::Errors;
use Text::Parser::Rule;

Moose::Exporter->setup_import_methods(
    with_meta => [
        'applies_rule', 'unwraps_lines_using', 'disables_superclass_rules'
    ],
    as_is => ['_check_custom_unwrap_args'],
    also  => 'Moose'
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
    traits  => ['Hash'],
    handles => {
        _class_has_rules      => 'exists',
        __cls_rule_order      => 'get',
        _set_class_rule_order => 'set',
    }
);

class_has _class_rules_in_order => (
    is      => 'rw',
    isa     => 'HashRef[ArrayRef[Text::Parser::Rule]]',
    lazy    => 1,
    default => sub { {} },
    traits  => ['Hash'],
    handles => {
        _are_rules_ordered  => 'exists',
        _class_rules        => 'get',
        _set_rules_of_class => 'set',
    },
);

sub _push_class_rule_order {
    my ( $class, $cls, $rulename ) = @_;
    my @ord = $class->class_rule_order($cls);
    push @ord, $rulename;
    $class->_set_class_rule_order( $cls => \@ord );
    $class->populate_class_rules($cls);
}

=meth class_rules

Takes a single string argument and returns the actual rule objects of the given class name.

    my (@rules) = Text::Parser::RuleSpec->class_rules('MyFavoriteParser');

=cut

sub class_rules {
    my ( $class, $cls ) = @_;
    return () if $class->class_has_no_rules($cls);
    @{ $class->_class_rules($cls) };
}

=meth class_rule_order

Takes a single string argument and returns the ordered list of rule names for the class.

    my (@order) = Text::Parser::RuleSpec->class_rule_order('MyFavoriteParser');

=cut

sub class_rule_order {
    my ( $class, $cls ) = @_;
    return () if not defined $cls;
    $class->_class_has_rules($cls) ? @{ $class->__cls_rule_order($cls) } : ();
}

=meth class_has_no_rules

Takes parser class name and returns a boolean representing if that class has any rules or not.

    print "There are no class rules for MyFavoriteParser.\n"
        if Text::Parser::RuleSpec->class_has_no_rules('MyFavoriteParser');

=cut

sub class_has_no_rules {
    my ( $this_cls, $cls ) = ( shift, shift );
    return 1 if not defined $cls;
    return 1 if not $this_cls->_class_has_rules($cls);
    return not $this_cls->class_rule_order($cls);
}

=meth populate_class_rules

Takes a parser class name as string argument. It populates the class rules according to the latest order of rules (returned by C<class_rule_order>).

    Text::Parser::RuleSpec->populate_class_rules('MyFavoriteParser');

=cut

sub populate_class_rules {
    my ( $class, $cls ) = @_;
    return if not defined $cls or not $class->_class_has_rules($cls);
    my @ord = $class->class_rule_order($cls);
    $class->_set_rules_of_class(
        $cls => [ map { $class->_get_rule($_) } @ord ] );
}

=head1 FUNCTIONS

The following methods are exported into the namespace of your class by default, and may only be called outside the C<main> namespace.

=func applies_rule

Takes one mandatory string argument which is a rule name, followed by the options to create a rule. These are the same as the arguments to the C<L<add_rule|Text::Parser/"add_rule">> method. Returns nothing. Exceptions will be thrown if any of the required arguments are not provided.

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
    _set_default_of_attribute( $meta, auto_split => 1 );
    _push_rule_order( $meta, $name );
}

sub _full_rule_name {
    my ( $meta, $name ) = ( shift, shift );
    return $meta->name . '/' . $name;
}

sub _excepts_apply_rule {
    my ( $meta, $name ) = ( shift, shift );
    _rule_must_have_name( $meta, $name );
    _check_arg_is_hash( $name, @_ );
    die main_cant_apply_rule( rule_name => $name ) if $meta->name eq 'main';
}

sub _rule_must_have_name {
    my ( $meta, $name ) = ( shift, shift );
    die spec_must_have_name( package_name => $meta->name )
        if not defined $name
        or ref($name) ne '';
}

sub _check_arg_is_hash {
    my $name = shift;
    die spec_requires_hash( rule_name => $name )
        if not @_
        or ( scalar(@_) % 2 );
}

sub _register_rule {
    my $key = shift;
    die name_rule_uniquely() if Text::Parser::RuleSpec->_exists_rule($key);
    my $rule = Text::Parser::Rule->new(@_);
    Text::Parser::RuleSpec->_add_new_rule( $key => $rule );
}

sub _set_default_of_attribute {
    my ( $meta, %val ) = @_;
    foreach my $k ( keys %val ) {
        my $old = $meta->find_attribute_by_name($k);
        my $new = $old->clone_and_inherit_options( default => $val{$k} );
        $meta->add_attribute($new);
    }
}

sub _push_rule_order {
    my ( $meta, $rule_name ) = ( shift, shift );
    _if_empty_prepopulate_rules_from_superclass($meta);
    Text::Parser::RuleSpec->_push_class_rule_order( $meta->name,
        _full_rule_name( $meta, $rule_name ) );
}

sub _if_empty_prepopulate_rules_from_superclass {
    my $meta = shift;
    Text::Parser::RuleSpec->_set_class_rule_order(
        $meta->name => _ordered_rules_of_classes( $meta->superclasses ) )
        if not Text::Parser::RuleSpec->_class_has_rules( $meta->name );
}

sub _ordered_rules_of_classes {
    return [ map { Text::Parser::RuleSpec->class_rule_order($_) } @_ ];
}

=func unwraps_lines_using

This function may be used if one wants to specify a custom line-unwrapping routine. Takes a hash argument with mandatory keys as follows:

    unwraps_lines_using(
        is_wrapped     => sub { # Should return a boolean for each $line
            1;
        }, 
        unwrap_routine => sub { # Should return a string for each $last and $line
            my ($self, $last, $line) = @_;
            $last.$line;
        }, 
    );

For the pair of routines to not cause unexpected C<undef> results, they should return defined values always. To effectively unwrap lines, the C<is_wrapped> routine should return a boolean C<1> when it encounters the continuation character, and C<unwrap_routine> should return a string that appropriately joins the last and current line together.

=cut

sub unwraps_lines_using {
    my $meta = shift;
    die main_cant_call_rulespec_func() if $meta->name eq 'main';
    my ( $is_wr, $un_wr ) = _check_custom_unwrap_args(@_);
    _set_lws_and_routines( $meta, $is_wr, $un_wr );
}

sub _check_custom_unwrap_args {
    die bad_custom_unwrap_call( err => 'Need 4 arguments' )
        if @_ != 4;
    _test_fields_unwrap_rtn(@_);
    my (%opt) = @_;
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

sub _set_lws_and_routines {
    my ( $meta, $is_wr, $unwr ) = @_;
    _set_default_of_attribute( $meta, line_wrap_style => 'custom' );
    _set_default_of_attribute( $meta, _is_wrapped     => sub { $is_wr; } );
    _set_default_of_attribute( $meta, _unwrap_routine => sub { $unwr; } );
}

=func disables_superclass_rules

Takes a list of rule names, or regular expression patterns, or any 

=cut

sub disables_superclass_rules {
    my $meta = shift;
    die main_cant_call_rulespec_func() if $meta->name eq 'main';
    _check_disable_rules_args(@_);
    _find_and_remove_superclass_rules( $meta, @_ );
}

sub _check_disable_rules_args {
    die bad_disable_rulespec_arg( arg => 'No arguments' ) if not @_;
    foreach my $a (@_) {
        _test_rule_type_and_string_val($a);
    }
}

my %disable_arg_types = ( '' => 1, 'Regexp' => 1, 'CODE' => 1 );

sub _test_rule_type_and_string_val {
    my $a      = shift;
    my $type_a = ref($a);
    die bad_disable_rulespec_arg( arg => $a )
        if not exists $disable_arg_types{$type_a};
    die rulename_for_disable_must_have_classname( rule => $a )
        if $type_a eq '' and $a !~ /\//;
}

sub _find_and_remove_superclass_rules {
    my $meta = shift;
    _if_empty_prepopulate_rules_from_superclass($meta);
    my @ord = _filtered_rules( $meta->name, @_ );
    Text::Parser::RuleSpec->_set_class_rule_order( $meta->name => \@ord );
    Text::Parser::RuleSpec->populate_class_rules( $meta->name );
}

sub _filtered_rules {
    my $cls = shift;
    local $_;
    map { _is_to_be_filtered( $_, $cls, @_ ) ? () : $_ }
        ( Text::Parser::RuleSpec->class_rule_order($cls) );
}

sub _is_to_be_filtered {
    my ( $r, $cls ) = ( shift, shift );
    my @c = split /\//, $r, 2;
    return 0 if $c[0] eq $cls;
    _test_each_filter_pattern( $r, @_ );
}

my %test_for_filter_type = (
    ''       => sub { $_[0] eq $_[1]; },
    'Regexp' => sub { $_[0] =~ $_[1]; },
    'CODE'   => sub { $_[1]->( $_[0] ); },
);

sub _test_each_filter_pattern {
    my $r = shift;
    foreach my $p (@_) {
        my $t = ref $p;
        return 1 if $test_for_filter_type{$t}->( $r, $p );
    }
    return 0;
}

__PACKAGE__->meta->make_immutable;

no Moose;
no MooseX::ClassAttribute;

1;
