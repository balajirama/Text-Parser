use strict;
use warnings;

package Text::Parser::ExAWK::Rule;

# ABSTRACT: Makes it possible to write AWK-style parsing rules for Text::Parser

use Moose;
use Text::Parser::Errors;
use Scalar::Util 'blessed';

=head1 SYNOPSIS

Users should not use this class directly to create and run rules. See L<Text::Parser::Manual::ExtendedAWKSyntax> for instructions on creating rules in a class. But the example below shows the way this class works for those that intend to improve the class.

    use Text::Parser::ExAWK::Rule;
    use Text::Parser;               # To demonstrate use with Text::Parser
    use Data::Dumper 'Dumper';      # To print any records

    my $rule = Text::Parser::ExAWK::Rule->new(
        if => '$1 eq "NAME:"', 
        do => 'my (@fld) = $this->field_range(1, -1); return "@fld";', 
    );

    # auto_split must be true to get any rules to work
    my $parser = Text::Parser->new(auto_split => 1);

    my @records = ();
    $rule->run($parser) if $rule->test($parser);
    print "Continuing to next rule..." if $rule->continue_to_next;

=head1 ATTRIBUTES

The attributes below may be used as options to C<new> constructor. Note that in some cases, the accessor method for the attribute is differently named. Use the attribute name in the constructor and accessor as a method.

=attr if (accessor C<condition>)

Read-write attribute. Must be string which after transformation must C<eval> successfully without compilation errors. This C<condition> is C<test>ed before the C<action> is C<run>. In the constructor, this attribute must be specified using C<if> option instead.

=cut

has condition => (
    is        => 'rw',
    isa       => 'Str',
    predicate => '_has_condition',
    init_arg  => 'if',
    trigger   => \&_set_condition,
);

sub _set_condition {
    my $self = shift;
    $self->_set_highest_nf;
    $self->_cond_sub_str( _gen_sub_str( $self->condition ) );
    $self->_cond_sub(
        _set_cond_sub( $self->condition, $self->_cond_sub_str ) );
}

sub _get_min_req_fields {
    my $str  = shift;
    my @indx = $str =~ /\$([0-9]+)|\$[{]([-][0-9]+)[}]/g;
    my @inds = sort { $b <=> $a } ( grep { defined $_ } @indx );
    return 0 if not @inds;
    ( $inds[0] >= -$inds[-1] ) ? $inds[0] : -$inds[-1];
}

my $SUB_BEGIN = 'sub {
    my $this = shift;
    local $_ = $this->this_line;
    return if not defined $this->this_line;
    ';

my $SUB_END = '
}';

sub _gen_sub_str {
    my $str  = shift;
    my $anon = $SUB_BEGIN . _replace_awk_vars($str) . $SUB_END;
    return $anon;
}

sub _replace_awk_vars {
    my $str = shift;
    $str =~ s/\$0/\$this->this_line/g;
    $str =~ s/\$[{]([-][0-9]+)[}]/\$this->field($1)/g;
    $str =~ s/\$([0-9]+)/\$this->field($1 - 1)/g;
    return $str;
}

has _cond_sub_str => (
    is       => 'rw',
    isa      => 'Str',
    init_arg => undef,
);

sub _set_cond_sub {
    my ( $rstr, $sub_str ) = @_;
    my $sub = eval $sub_str;
    _throw_bad_cond( $rstr, $sub_str, $@ ) if not defined $sub;
    return $sub;
}

sub _throw_bad_cond {
    my ( $code, $sub_str, $msg ) = @_;
    die bad_rule_syntax(
        code       => $code,
        msg        => $msg,
        subroutine => $sub_str,
    );
}

has _cond_sub => (
    is       => 'rw',
    isa      => 'CodeRef',
    init_arg => undef,
);

=attr min_nf

Read-only attribute. Gets adjusted automatically.

    print "Rule requires a minimum of ", $rule->min_nf, " fields on the line.\n";

=cut

has min_nf => (
    is       => 'ro',
    isa      => 'Num',
    traits   => ['Number'],
    init_arg => undef,
    default  => 0,
    lazy     => 1,
    handles  => { _set_min_nf => 'set', }
);

sub _set_highest_nf {
    my $self = shift;
    my $nf   = _get_min_req_fields( $self->_gen_joined_str );
    $self->_set_min_nf($nf);
}

sub _gen_joined_str {
    my $self = shift;
    my (@strs) = ();
    push @strs, $self->condition            if $self->_has_condition;
    push @strs, $self->action               if $self->_has_action;
    push @strs, $self->_join_preconds('; ') if not $self->_no_preconds;
    my $str = join '; ', @strs;
}

=attr action

Must be string which after transformation must C<eval> successfully without compilation errors. The C<action> returns a value which may be stored as a record by the caller.

    $rule->action('')

=cut

has action => (
    is        => 'rw',
    isa       => 'Str',
    init_arg  => 'do',
    predicate => '_has_action',
    trigger   => \&_set_action,
);

sub _set_action {
    my $self = shift;
    $self->_set_highest_nf;
    $self->_act_sub_str( _gen_sub_str( $self->action ) );
    $self->_act_sub( _set_cond_sub( $self->action, $self->_act_sub_str ) );
}

has _act_sub => (
    is       => 'rw',
    isa      => 'CodeRef',
    init_arg => undef,
);

has _act_sub_str => (
    is       => 'rw',
    isa      => 'Str',
    init_arg => undef,
);

=attr dont_record

Boolean indicating if return value of the C<action> (when transformed and C<eval>uated) should be stored in the parser as a record.

    print "Will not save records\n" if $rule->dont_record;

The accessor is already being handled and used in C<L<run|/run>> method. Usually the results of the C<eval>uated C<action> are recorded in the object passed to C<run>. But when this attribute is set to true, then results are not recorded.

=cut

has dont_record => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    trigger => \&_check_continue_to_next,
);

sub _check_continue_to_next {
    my $self = shift;
    return if not $self->continue_to_next;
    die illegal_rule_cont if not $self->dont_record;
}

=attr continue_to_next

Takes a boolean value. This can be set true only for rules with C<dont_record> attribute set to a true value. This attribute indicates that the rule will proceed to the next rule until some rule passes the C<test>. So if you have a series of rules to test and execute in sequence:

    foreach my $rule (@rules) {
        next if not $rule->test($parser);
        $rule->run($parser);
        break if not $rule->continue_to_next;
    }

=cut

has continue_to_next => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    trigger => \&_check_continue_to_next,
);

=constr new

Takes optional attributes described in L<ATTRIBUTES|/ATTRIBUTES> section.

    my $rule = Text::Parser::ExAWK::Rule->new(
        condition => '$1 eq "NAME:"',   # Some condition string
        action => 'return $2;',         # Some action to do when condition is met
        dont_record => 1,               # Directive to not record
        continue_to_next => 1,          # Directive to next rule till another rule
                                        # passes test condition
    );

=cut

sub BUILD {
    my $self = shift;
    die illegal_rule_no_if_no_act
        if not $self->_has_condition and not $self->_has_action;
    $self->action('return $0;') if not $self->_has_action;
    $self->condition(1)         if not $self->_has_condition;
}

=head1 METHODS

=method add_precondition

Takes a list of rule strings that are similar to the C<condition> string.

=cut

has _preconditions => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    init_arg => undef,
    default  => sub { [] },
    lazy     => 1,
    traits   => ['Array'],
    handles  => {
        _preconds        => 'elements',
        add_precondition => 'push',
        _join_preconds   => 'join',
        _get_precond     => 'get',
        _no_preconds     => 'is_empty',
    },
);

after add_precondition => sub {
    my $self = shift;
    $self->_set_highest_nf;
    my $str    = $self->_get_precond(-1);
    my $substr = _gen_sub_str($str);
    $self->_add_precond_substr($substr);
    $self->_add_precond_sub( _set_cond_sub( $str, $substr ) );
};

has _precondition_substrs => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    init_arg => undef,
    default  => sub { [] },
    lazy     => 1,
    traits   => ['Array'],
    handles  => {
        _precond_substrs    => 'elements',
        _add_precond_substr => 'push',
    }
);

has _precond_subroutines => (
    is       => 'ro',
    isa      => 'ArrayRef[CodeRef]',
    init_arg => undef,
    default  => sub { [] },
    lazy     => 1,
    traits   => ['Array'],
    handles  => {
        _precond_subs    => 'elements',
        _add_precond_sub => 'push',
    }
);

=method test

Takes one argument that must be of type C<Text::Parser> (or some inherited class of that). Returns a boolean value indicating if the C<run> method may be called. Inside C<test>, each of these conditions must pass before the C<condition> is tested. If all preconditions and C<condition> pass, then C<test> returns true.

=cut

sub test {
    my $self = shift;
    return 0 if not _check_parser_arg(@_);
    my $parser = shift;
    return 0 if not $parser->can('NF') or $parser->NF < $self->min_nf;
    return 0 if not $self->_test_preconditions($parser);
    return $self->_test_cond_sub($parser);
}

sub _check_parser_arg {
    return 0 if not @_;
    my $parser = shift;
    return 0 if not defined blessed($parser);
    $parser->isa('Text::Parser');
}

sub _test_preconditions {
    my ( $self, $parser ) = @_;
    foreach my $cond ( $self->_precond_subs ) {
        return 0 if not $cond->($parser);
    }
    return 1;
}

sub _test_cond_sub {
    my ( $self, $parser ) = @_;
    my $cond = $self->_cond_sub;
    return 0 if not defined $parser->this_line;
    return $cond->($parser);
}

=method run

Takes one argument that must be of type C<Text::Parser> or its derivative. Has no return value.

=cut

sub run {
    my $self = shift;
    die rule_run_improperly if not _check_parser_arg(@_);
    return if $self->action !~ /\S+/;
    my (@res) = $self->_call_act_sub( $_[0] );
    return if $self->dont_record;
    $_[0]->push_records(@res);
}

sub _call_act_sub {
    my ( $self, $parser ) = @_;
    my $act = $self->_act_sub;
    return ( $act->($parser) );
}

__PACKAGE__->meta->make_immutable;

no Moose;

=head1 SEE ALSO

=for :list
* L<Text::Parser>
* L<"The AWK Programming Language"|https://books.google.com/books?id=53ueQgAACAAJ&dq=The+AWK+Programming+Language&hl=en&sa=X&ei=LXxXVfq0GMOSsAWrpoC4Bg&ved=0CCYQ6AEwAA> by Alfred V. Aho, Brian W. Kernighan, and Peter J. Weinberger, Addison-Wesley, 1988. ISBN 0-201-07981-X

=cut

1;

