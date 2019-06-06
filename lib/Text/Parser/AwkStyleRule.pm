use strict;
use warnings;

package Text::Parser::AwkStyleRule;

# ABSTRACT: AWK-style rules for parsing and extracting records

use Moose;
use Text::Parser::Errors;

has condition => (
    is      => 'ro',
    isa     => 'Str',
    default => '1',
);

has _cond_sub => (
    is       => 'rw',
    isa      => 'CodeRef',
    init_arg => undef,
);

has _cond_sub_str => (
    is       => 'rw',
    isa      => 'Str',
    init_arg => undef,
);

has action => (
    is      => 'ro',
    isa     => 'Str',
    default => 'return $0;',
);

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

has _max_index => (
    is       => 'rw',
    isa      => 'Num',
    init_arg => undef,
    default  => -1,
);

sub BUILD {
    my $self = shift;
    $self->_max_index(
        _get_max_index( $self->condition . '; ' . $self->action ) );
    $self->_gen_cond_sub_str;
    $self->_set_cond_sub;
    $self->_gen_act_sub_str;
    $self->_set_act_sub;
}

sub _get_max_index {
    my $str  = shift;
    my @indx = $str =~ /\$([0-9]+)|\$[{]([-][0-9]+)[}]/g;
    my @inds = sort { $b <=> $a } ( grep { defined $_ } @indx );
    return -1 if not @inds;
    ( $inds[0] >= -$inds[-1] ) ? $inds[0] : -$inds[-1];
}

my $SUB_BEGIN = 'sub {
    my $this = shift;
    local $_ = $this->this_line;';

my $COND_SUB_BEGIN = $SUB_BEGIN . '
    return 1 if ($this->NF > ';

my $COND_SUB_END = ');
    return 0;
}';

sub _gen_cond_sub_str {
    my $self = shift;
    my $anon = $COND_SUB_BEGIN . $self->_max_index;
    $anon .= ') and (' . _replace_awk_vars( $self->condition );
    $anon .= $COND_SUB_END;
    $self->_cond_sub_str($anon);
}

sub _replace_awk_vars {
    my $str = shift;
    $str =~ s/\$0/\$this->this_line/g;
    $str =~ s/\$[{]([-][0-9]+)[}]/\$this->field($1)/g;
    $str =~ s/\$([0-9]+)/\$this->field($1 - 1)/g;
    return $str;
}

sub _set_cond_sub {
    my $self = shift;
    my $sub  = eval $self->_cond_sub_str;
    $self->_throw_bad_cond($@) if not defined $sub;
    $self->_cond_sub($sub);
}

sub _throw_bad_cond {
    my ( $self, $msg ) = ( shift, shift );
    die bad_rule_syntax(
        code       => $self->condition,
        msg        => $msg,
        subroutine => $self->_cond_sub_str
    );
}

sub _gen_act_sub_str {
    my $self = shift;
    my $anon = $SUB_BEGIN . "\n\t" . _replace_awk_vars( $self->action );
    $anon .= "\n" . '}';
    $self->_act_sub_str($anon);
}

sub _set_act_sub {
    my $self = shift;
    my $sub  = eval $self->_act_sub_str;
    $self->_throw_bad_act($@) if not defined $sub;
    $self->_act_sub($sub);
}

sub _throw_bad_act {
    my ( $self, $msg ) = ( shift, shift );
    die bad_rule_syntax(
        code       => $self->action,
        msg        => $msg,
        subroutine => $self->_act_sub_str
    );
}

__PACKAGE__->meta->make_immutable;

no Moose;

1;

