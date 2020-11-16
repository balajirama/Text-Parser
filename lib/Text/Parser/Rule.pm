use strict;
use warnings;

package Text::Parser::Rule;

# ABSTRACT: Makes it possible to write AWK-style parsing rules for Text::Parser

use Moose;
use Text::Parser::Error;
use Scalar::Util 'blessed', 'looks_like_number';
use String::Util ':all';
use List::Util qw(reduce any all none notall first
    max maxstr min minstr product sum sum0 pairs
    unpairs pairkeys pairvalues pairfirst
    pairgrep pairmap shuffle uniq uniqnum uniqstr
);
use Try::Tiny;

=head1 SYNOPSIS

    use Text::Parser;

    my $parser = Text::Parser->new();
    $parser->add_rule(
        if               => '$1 eq "NAME:"',      # Some condition string
        do               => 'return $2;',         # Some action to do when condition is met
        dont_record      => 1,                    # Directive to not record
        continue_to_next => 1,                    # Directive to next rule till another rule
    );
    $parser->read(shift);

=head1 DESCRIPTION

This class is never used directly. Instead rules are created and managed in one of two ways:

=for :list
* via the C<L<add_rule|Text::Parser/"add_rule">> method of L<Text::Parser>
* using C<L<applies_rule|Text::Parser::RuleSpec/"applies_rule">> function from L<Text::Parser::RuleSpec>

In both cases, the arguments are the same.

=head1 METHODS

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
    $self->_has_blank_condition(0);
    $self->_set_highest_nf;
    $self->_cond_sub_str( _gen_sub_str( $self->condition ) );
    $self->_cond_sub(
        _set_cond_sub( $self->condition, $self->_cond_sub_str ) );
}

has _has_blank_condition => (
    is      => 'rw',
    isa     => 'Bool',
    lazy    => 1,
    default => 1,
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

sub _get_min_req_fields {
    my $str = shift;
    my @indx
        = $str =~ /\$([0-9]+)|\$[{]([-][0-9]+)[}]|[$][{]([-]?[0-9]+)[+][}]/g;
    my @inds = sort { $b <=> $a } ( grep { defined $_ } @indx );
    return 0 if not @inds;
    ( $inds[0] >= -$inds[-1] ) ? $inds[0] : -$inds[-1];
}

my $SUB_BEGIN = 'sub {
    my $this = shift;
    my $__ = $this->_ExAWK_symbol_table;
    local $_ = $this->this_line;
    ';

my $SUB_END = '
}';

sub _gen_sub_str {
    my $str  = shift;
    my $anon = $SUB_BEGIN . _replace_awk_vars($str) . $SUB_END;
    return $anon;
}

sub _replace_awk_vars {
    local $_ = shift;
    _replace_positional_indicators();
    _replace_range_shortcut();
    _replace_exawk_vars() if m/[~][a-z_][a-z0-9_]+/i;
    return $_;
}

sub _replace_positional_indicators {
    s/\$0/\$this->this_line/g;
    s/\$[{]([-][0-9]+)[}]/\$this->field($1)/g;
    s/\$([0-9]+)/\$this->field($1-1)/g;
}

sub _replace_range_shortcut {
    s/\$[{]([-][0-9]+)[+][}]/\$this->join_range($1)/g;
    s/\$[{]([0-9]+)[+][}]/\$this->join_range($1-1)/g;
    s/\\\@[{]([-][0-9]+)[+][}]/[\$this->field_range($1)]/g;
    s/\\\@[{]([0-9]+)[+][}]/[\$this->field_range($1-1)]/g;
    s/\@[{]([-][0-9]+)[+][}]/\$this->field_range($1)/g;
    s/\@[{]([0-9]+)[+][}]/\$this->field_range($1-1)/g;
}

sub _replace_exawk_vars {
    my (@varnames) = _uniq( $_ =~ /[~]([a-z_][a-z0-9_]+)/ig );
    foreach my $var (@varnames) {
        my $v = '~' . $var;
        s/$v/\$__->{$var}/g;
    }
}

sub _uniq {
    my (%elem) = map { $_ => 1 } @_;
    return ( keys %elem );
}

has _cond_sub_str => (
    is       => 'rw',
    isa      => 'Str',
    init_arg => undef,
);

sub _set_cond_sub {
    my ( $rstr, $sub_str ) = @_;
    my $sub = eval $sub_str;
    parser_exception("Bad rule syntax $rstr: $@: $sub_str")
        if not defined $sub;
    return $sub;
}

has _cond_sub => (
    is       => 'rw',
    isa      => 'CodeRef',
    init_arg => undef,
);

has min_nf => (
    is       => 'ro',
    isa      => 'Num',
    traits   => ['Number'],
    init_arg => undef,
    default  => 0,
    lazy     => 1,
    handles  => { _set_min_nf => 'set', }
);

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
    parser_exception(
        "Rule cannot continue to next if action result is recorded")
        if not $self->dont_record;
}

=method continue_to_next

Method called internally in L<Text::Parser>. By default, if the C<if> condition passes for a line, then that is the last rule executed for that line. But when C<continue_to_next> is set to a true value, the parser will continue to run the next rule in sequence, even though the C<if> block for this rule passed.

=cut

has continue_to_next => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    trigger => \&_check_continue_to_next,
);

sub BUILD {
    my $self = shift;
    parser_exception("Rule created without required components")
        if not $self->_has_condition and not $self->_has_action;
    $self->action('return $0;') if not $self->_has_action;
    $self->_constr_condition    if not $self->_has_condition;
}

sub _constr_condition {
    my $self = shift;
    $self->condition(1);
    $self->_has_blank_condition(1);
}

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

Method called internally in L<Text::Parser>. Runs code in C<if> block.

=cut

sub test {
    my $self = shift;
    return 0 if not _check_parser_arg(@_);
    my $parser = shift;
    return 0 if not $parser->auto_split;
    return $self->_test($parser);
}

sub _check_parser_arg {
    return 0 if not @_;
    my $parser = shift;
    return 0 if not defined blessed($parser);
    $parser->isa('Text::Parser');
}

sub _test {
    my ( $self, $parser ) = ( shift, shift );
    return 0 if $parser->NF < $self->min_nf;
    return 0
        if not( $self->_no_preconds or $self->_test_preconditions($parser) );
    return 1 if $self->_has_blank_condition;
    return $self->_test_cond_sub($parser);
}

sub _test_preconditions {
    my ( $self, $parser ) = @_;
    foreach my $cond ( $self->_precond_subs ) {
        my $val = $cond->($parser);
        return 0 if not defined $val or not $val;
    }
    return 1;
}

sub _test_cond_sub {
    my ( $self, $parser ) = @_;
    my $cond = $self->_cond_sub;
    return 0 if not defined $parser->this_line;
    my $val = $cond->($parser);
    defined $val and $val;
}

=method run

Method called internally in L<Text::Parser>. Runs code in C<do> block, and saves the result as a record depending on C<dont_record>.

=cut

sub run {
    my $self = shift;
    parser_exception("Method run on rule was called without a parser object")
        if not _check_parser_arg(@_);
    return if not $_[0]->auto_split;
    push @_, 1 if @_ < 2;
    $self->_run(@_);
}

sub _run {
    my ( $self, $parser ) = ( shift, shift );
    return if nocontent( $self->action );
    my (@res) = $self->_call_act_sub( $parser, @_ );
    return if $self->dont_record;
    $parser->push_records(@res);
}

sub _call_act_sub {
    my ( $self, $parser, $test_line ) = @_;
    return if $test_line and not defined $parser->this_line;
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

