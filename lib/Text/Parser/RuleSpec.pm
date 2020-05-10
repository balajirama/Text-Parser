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

=head1 DESCRIPTION

=head2 Primary usage

The primary purpose of this class is to enable users to create their own parser classes for a well-established text file format. Sometimes, there is a relatively complex text file format and a parser for that could be written allowing for code to be shared across multiple programs. The basic steps are as following:

    package MyFavoriteParser;
    use Text::Parser::RuleSpec;
    extends 'Text::Parser';

That's it! This is the basic / bare-minimum requirement to make your own text parser. But it is not particularly useful at this point without any rules of its own.

    applies_rule comment_char => (
        if          => '$1 =~ /^#/;', 
        dont_record => 1, 
    );

This above rule ignores all comment lines and is added to C<MyFavoriteParser> class. So now when you create an instance of C<MyFavoriteParser>, it would automatically run this rule when you call C<L<read|Text::Parser/read>>.

We can preset any attributes for this parser class using the familiar L<Moose> functions. Here is an example:

    has '+line_wrap_style' => (
        default => 'trailing_backslash', 
        is      => 'ro', 
    );

    has '+auto_trim' => (
        default => 'b', 
        is      => 'ro', 
    );

=head2 Using attributes for storage

Sometimes, you may want to store the parsed information in attributes, instead of records. So for example:

    has current_section => (
        is      => 'rw', 
        isa     => 'Str|Undef', 
        default => undef, 
        lazy    => 1, 
    );

    has _num_lines_by_section => (
        is      => 'rw', 
        isa     => 'HashRef[Int]', 
        default => sub { {}; }, 
        lazy    => 1, 
        handles => {
            num_lines      => 'get', 
            _set_num_lines => 'set', 
        }
    );

    applies_rule inc_section_num_lines => (
        if          => '$1 ne "SECTION"', 
        do          => 'my $sec = $this->current_section;
                        my $n = $this->num_lines($sec); 
                        $this->_set_num_lines($sec => $n+1);', 
        dont_record => 1, 
    );

    applies_rule get_section_name => (
        if          => '$1 eq "SECTION"', 
        do          => '$this->current_section($2); $this->_set_num_lines($2 => 0);', 
        dont_record => 1, 
    );

In the above example, you can see how the section name we get from one rule is used in a different rule.

=head2 Inheriting rules in subclasses

We can further subclass a class that C<extends> L<Text::Parser>. Inheriting the rules of the superclass is automatic:

    package MyParser1;
    use Text::Parser::RuleSpec;

    extends 'Text::Parser';

    applies_rule rule1 => (
        do => '# something', 
    );

    package MyParser2;
    use Text::Parser::RuleSpec;

    extends 'MyParser1';

    applies_rule rule1 => (
        do => '# something else', 
    );

Now, C<MyParser2> contains two rules: C<MyParser/rule1> and C<MyParser2/rule1>. By default, rules of superclasses will be run before rules in the subclass. The derived class can change this:

    package MyParser2;
    use Text::Parser::RuleSpec;

    extends 'MyParser1';

    applies_rule rule1 => (
        do     => '# something else', 
        before => 'MyParser1/rule1', 
    );

A subclass may choose to disable any superclass rules:

    package MyParser3;
    use Text::Parser::RuleSpec;

    extends 'MyParser2';

    disables_superclass_rules qr/^MyParser1/;  # disables all rules from MyParser1 class

Or to clone a rule from either the same class, or from a superclass, or even from some other random class.

    package ClonerParser;
    use Text::Parser::RuleSpec;

    use Some::Parser;  # contains rules: "heading", "section"
    extends 'MyParser2';

    applies_rule my_own_rule => (
        if    => '# check something', 
        do    => '# collect some data', 
        after => 'MyParser2/rule1', 
    );

    applies_cloned_rule 'MyParser2/rule1' => (
        add_precondition => '# Additional condition', 
        do               => '# Optionally change the action', 
        # prepend_action => '# Or just prepend something', 
        # append_action  => '# Or append something', 
        after            => 'MyParser1/rule1', 
    );

So essentially, programmer A may write a text parser for a text syntax SYNT1, and programmer B notices that the text syntax he wishes to parse (SYNT2) is similar, except for a few differences. Instead of having to re-write the parsing algorithm from scratch, he can just extend the code from programmer A and modify it exactly as needed. This is especially useful when syntax many different text formats are very similar.

=head1 METHODS

All methods can be called directly on the C<Text::Parser::RuleSpec> class directly.

=cut

use Moose;
use Moose::Exporter;
use MooseX::ClassAttribute;
use Text::Parser::Errors;
use Text::Parser::Rule;
use List::MoreUtils qw(before_incl after_incl);

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

=method class_rules

Takes a single string argument and returns the actual rule objects of the given class name.

    my (@rules) = Text::Parser::RuleSpec->class_rules('MyFavoriteParser');

=cut

sub class_rules {
    my ( $class, $cls ) = @_;
    return () if $class->class_has_no_rules($cls);
    @{ $class->_class_rules($cls) };
}

=method class_rule_order

Takes a single string argument and returns the ordered list of rule names for the class.

    my (@order) = Text::Parser::RuleSpec->class_rule_order('MyFavoriteParser');

=cut

sub class_rule_order {
    my ( $class, $cls ) = @_;
    return () if not defined $cls;
    $class->_class_has_rules($cls) ? @{ $class->__cls_rule_order($cls) } : ();
}

=method class_has_no_rules

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

=method populate_class_rules

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

Takes one mandatory string argument - a rule name - followed by the options to create a rule. These are the same as the arguments to the C<L<add_rule|Text::Parser/"add_rule">> method of L<Text::Parser> class. Returns nothing. Exceptions will be thrown if any of the required arguments are not provided.

    applies_rule print_emails => (
        if               => '$1 eq "EMAIL:"', 
        do               => 'print $2;', 
        dont_record      => 1, 
        continue_to_next => 1, 
    );

Optionally, one may additionally provide one of the options C<before> or C<after> and specify a superclass rule.

    applies_rule check_line_syntax => (
        if     => '$1 ne "SECTION"', 
        do     => '$this->check_syntax($this->current_section, $_);', 
        before => 'Parent::Parser/add_line_to_data_struct', 
    );

Exceptions will be thrown if the C<before> or C<after> rule does not have a class name in it, or if it is the same as the current class, or if the rule is not among the inherited rules so far.

=cut

sub applies_rule {
    my ( $meta, $name ) = ( shift, shift );
    _first_things_on_applies_rule( $meta, $name, @_ );
    _register_rule( _full_rule_name( $meta, $name ), @_ );
    _set_correct_rule_order( $meta, $name, @_ );
}

sub _first_things_on_applies_rule {
    my ( $meta, $name ) = ( shift, shift );
    _excepts_apply_rule( $meta, $name, @_ );
    _set_default_of_attributes( $meta, auto_split => 1 );
}

sub _full_rule_name {
    my ( $meta, $name ) = ( shift, shift );
    return $meta->name . '/' . $name;
}

sub _excepts_apply_rule {
    my ( $meta, $name ) = ( shift, shift );
    die main_cant_apply_rule( rule_name => $name ) if $meta->name eq 'main';
    _rule_must_have_name( $meta, $name );
    _check_args_hash_stuff( $meta, $name, @_ );
}

my %rule_options = (
    if               => 1,
    do               => 1,
    dont_record      => 1,
    continue_to_next => 1,
    before           => 1,
    after            => 1,
);

sub _rule_must_have_name {
    my ( $meta, $name ) = ( shift, shift );
    die spec_must_have_name( package_name => $meta->name )
        if not defined $name
        or ( '' ne ref($name) )
        or ( exists $rule_options{$name} );
}

sub _check_args_hash_stuff {
    my ( $meta, $name ) = ( shift, shift );
    my (%opt) = _check_arg_is_hash( $name, @_ );
    _if_empty_prepopulate_rules_from_superclass($meta);
    _check_rule_order_args( $meta, $name, %opt )
        if _has_location_opts(%opt);
}

sub _has_location_opts {
    my (%opt) = @_;
    exists $opt{before} or exists $opt{after};
}

sub _check_arg_is_hash {
    my $name = shift;
    die spec_requires_hash( rule_name => $name )
        if not @_
        or ( scalar(@_) % 2 );
    return @_;
}

sub _check_rule_order_args {
    my ( $meta, $name, %opt ) = ( shift, shift, @_ );
    die only_one_of_before_or_after( rule => $name )
        if exists $opt{before} and exists $opt{after};
    my $loc = exists $opt{before} ? 'before' : 'after';
    my ( $cls, $rule ) = split /\//, $opt{$loc}, 2;
    die before_or_after_needs_classname( rule => $name )
        if not defined $rule;
    die ref_to_non_existent_rule( rule => $opt{$loc} )
        if not Text::Parser::RuleSpec->_exists_rule( $opt{$loc} );
    my (@r) = Text::Parser::RuleSpec->class_rule_order( $meta->name );
    my $is_super_rule = grep { $_ eq $opt{$loc} } @r;
    die before_or_after_only_superclass_rules( rule => $name )
        if $cls eq $meta->name or not $is_super_rule;
}

sub _register_rule {
    my $key = shift;
    die name_rule_uniquely() if Text::Parser::RuleSpec->_exists_rule($key);
    my $rule = Text::Parser::Rule->new( _get_rule_opts_only(@_) );
    Text::Parser::RuleSpec->_add_new_rule( $key => $rule );
}

sub _get_rule_opts_only {
    my (%opt) = @_;
    delete $opt{before} if exists $opt{before};
    delete $opt{after}  if exists $opt{after};
    return (%opt);
}

sub _set_default_of_attributes {
    my ( $meta, %val ) = @_;
    while ( my ( $k, $v ) = ( each %val ) ) {
        _inherit_set_default_mk_ro( $meta, $k, $v )
            if not defined $meta->get_attribute($k);
    }
}

sub _inherit_set_default_mk_ro {
    my ( $meta, $attr, $def ) = ( shift, shift, shift );
    my $old = $meta->find_attribute_by_name($attr);
    my $new = $old->clone_and_inherit_options( default => $def, is => 'ro' );
    $meta->add_attribute($new);
}

sub _set_correct_rule_order {
    my ( $meta, $rule_name ) = ( shift, shift );
    my $rname = _full_rule_name( $meta, $rule_name );
    return _push_to_class_rules( $meta->name, $rname )
        if not _has_location_opts(@_);
    _insert_rule_in_order( $meta->name, $rname, @_ );
}

my %INSERT_RULE_FUNC = (
    before => \&_ins_before_rule,
    after  => \&_ins_after_rule,
);

sub _insert_rule_in_order {
    my ( $cls, $rname, %opt ) = ( shift, shift, @_ );
    my $loc = exists $opt{before} ? 'before' : 'after';
    $INSERT_RULE_FUNC{$loc}->( $cls, $opt{$loc}, $rname );
    Text::Parser::RuleSpec->populate_class_rules($cls);
}

sub _ins_before_rule {
    my ( $cls, $before, $rname ) = ( shift, shift, shift );
    my (@ord)  = Text::Parser::RuleSpec->class_rule_order($cls);
    my (@ord1) = before_incl { $_ eq $before } @ord;
    my (@ord2) = after_incl { $_ eq $before } @ord;
    pop @ord1;
    Text::Parser::RuleSpec->_set_class_rule_order(
        $cls => [ @ord1, $rname, @ord2 ] );
}

sub _ins_after_rule {
    my ( $cls, $after, $rname ) = ( shift, shift, shift );
    my (@ord)  = Text::Parser::RuleSpec->class_rule_order($cls);
    my (@ord1) = before_incl { $_ eq $after } @ord;
    my (@ord2) = after_incl { $_ eq $after } @ord;
    shift @ord2;
    Text::Parser::RuleSpec->_set_class_rule_order(
        $cls => [ @ord1, $rname, @ord2 ] );
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

sub _push_to_class_rules {
    my ( $class, $cls, $rulename ) = ( 'Text::Parser::RuleSpec', @_ );
    my @ord = $class->class_rule_order($cls);
    push @ord, $rulename;
    $class->_set_class_rule_order( $cls => \@ord );
    $class->populate_class_rules($cls);
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
    _set_default_of_attributes( $meta, line_wrap_style => 'custom' );
    _set_default_of_attributes( $meta, _is_wrapped     => sub { $is_wr; } );
    _set_default_of_attributes( $meta, _unwrap_routine => sub { $unwr; } );
}

=func disables_superclass_rules

Takes a list of rule names, or regular expression patterns, or subroutine references to identify rules that are to be disabled. You cannot disable rules of the same class.

A string argument is expected to contain the full rule-name (including class name) in the format C<My::Parser::Class/my_rule>. The C</> (slash) separating the class name and rule name is mandatory.

A regexp argument is tested against the full rule-name.

If a subroutine reference is provided, the subroutine is called for each rule in the class, and the rule is disabled if the subroutine returns a true value.

    disables_superclass_rules qw(Parent::Parser::Class/parent_rule Another::Class/another_rule);
    disables_superclass_rules qr/Parent::Parser::Class\/comm.*/;
    disables_superclass_rules sub {
        my $rulename = shift;
        $rulename =~ /[@]/;
    };

=cut

sub disables_superclass_rules {
    my $meta = shift;
    die main_cant_call_rulespec_func() if $meta->name eq 'main';
    _check_disable_rules_args( $meta->name, @_ );
    _find_and_remove_superclass_rules( $meta, @_ );
}

sub _check_disable_rules_args {
    my $cls = shift;
    die bad_disable_rulespec_arg( arg => 'No arguments' ) if not @_;
    foreach my $a (@_) {
        _test_rule_type_and_val( $cls, $a );
    }
}

my %disable_arg_types = ( '' => 1, 'Regexp' => 1, 'CODE' => 1 );

sub _test_rule_type_and_val {
    my $type_a = ref( $_[1] );
    die bad_disable_rulespec_arg( arg => $_[1] )
        if not exists $disable_arg_types{$type_a};
    _test_rule_string_val(@_) if $type_a eq '';
}

sub _test_rule_string_val {
    my ( $cls, $a ) = ( shift, shift );
    die rulename_for_disable_must_have_classname( rule => $a ) if $a !~ /\//;
    my @c = split /\//, $a, 2;
    die cant_disable_same_class_rules( rule => $a ) if $c[0] eq $cls;
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
    map { _is_to_be_filtered( $_, @_ ) ? () : $_ }
        ( Text::Parser::RuleSpec->class_rule_order($cls) );
}

my %test_for_filter_type = (
    ''       => sub { $_[0] eq $_[1]; },
    'Regexp' => sub { $_[0] =~ $_[1]; },
    'CODE'   => sub { $_[1]->( $_[0] ); },
);

sub _is_to_be_filtered {
    my $r = shift;
    foreach my $p (@_) {
        my $t = ref $p;
        return 1 if $test_for_filter_type{$t}->( $r, $p );
    }
    return 0;
}

=func applies_cloned_rule

Clones an existing rule to make a replica, but you can add options to change any parameters of the rule.

=cut

__PACKAGE__->meta->make_immutable;

no Moose;
no MooseX::ClassAttribute;

1;
