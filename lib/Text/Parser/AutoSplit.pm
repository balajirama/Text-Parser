use strict;
use warnings;

package Text::Parser::AutoSplit;

# VERSION

# ABSTRACT: A role that adds the ability to auto-split a line into fields

use Moose::Role;
use MooseX::CoverableModifiers;
use List::Util qw(first);
use List::SomeUtils qw(first_index);
use Text::Parser::Error;
use English;

=head1 SYNOPSIS

    use Text::Parser;

    my $p1 = Text::Parser->new();
    $p1->read('/path/to/file');
    my $p2 = Text::Parser->new();
    $p2->add_rule( do => '$this->field(0);' );
        ## add_rule method automatically sets up auto_split
    $p2->read('/another/file');

=head1 DESCRIPTION

C<Text::Parser::AutoSplit> is a role that is automatically composed into an object of L<Text::Parser> if the C<auto_split> attribute is set during object construction, or when C<L<add_rule|Text::Parser/"add_rule">> method is called. The field separator is controlled by another C<Text::Parser> attribute C<L<FS|Text::Parser/"FS">>.

When the C<auto_split> attribute is set to a true value, the object of C<Text::Parser> will be able to use methods described in this role.

=cut

requires '_set_this_line', 'FS', '_clear_this_line', 'this_line',
    'auto_split';

sub _set_fields {
    my $self = shift;
    $self->{_fields} = shift;
}

=head1 METHODS AVAILABLE ON AUTO-SPLIT

These methods become available when C<auto_split> attribute is true. A runtime error will be thrown if they are called without C<auto_split> being set. They can be used inside a subclass or in the rules.

=auto_split_meth NF

The name of this method comes from the C<NF> variable in the popular L<GNU Awk program|https://www.gnu.org/software/gawk/gawk.html>.

Returns the number of fields on a line. The field separator is specified with C<FS> attribute.

    $parser->applies_rule(
        if          => '$this->NF >= 2'
        do          => '$this->collect_info($2);', 
        dont_record => 1, 
    );

If your rule contains any positional identifiers (like C<$1>, C<$2>, C<$3> etc., to identify the field) the rule automatically checks that there are at least as many fields as the largest positional identifier. So the above rule could also be written as:

    $parser->applies_rule(
        do          => '$this->collect_info($2);', 
        dont_record => 1, 
    );

It has the same results.

=cut

sub NF {
    my $self = shift;
    return $#{ $self->{_fields} } + 1;
}

=auto_split_meth fields

Takes no argument and returns all the fields as an array. The C<FS> field separator controls how fields are defined. Leading and trailing spaces are trimmed.

    $parser->add_rule( do => 'return [ $this->fields ];' );

=cut

sub fields {
    my $self = shift;
    return ( @{ $self->{_fields} } );
}

=auto_split_meth field

Takes an integer argument and returns the field whose index is passed as argument.

    $parser->add_rule(
        if          => '$this->field(0) eq "END"', 
        do          => '$this->abort_reading;', 
        dont_record => 1, 
    );

You can specify negative elements to start counting from the end. For example index C<-1> is the last element, C<-2> is the penultimate one, etc. Let's say the following is the text on a line in a file:

    THIS           IS          SOME           TEXT
    field(0)      field(1)    field(2)      field(3)
    field(-4)    field(-3)   field(-2)     field(-1)

=cut

sub field {
    my ( $self, $i ) = ( shift, shift );
    parser_exception("Field index must be numeric") if $i !~ /\d+/;
    return $self->{_fields}->[$i];
}

=auto_split_meth field_range

Takes two optional integers C<$i> and C<$j> as arguments and returns an array, where the first element is C<field($i)>, the second C<field($i+1)>, and so on, till C<field($j)>.

    $parser->add_rule(
        if => '$1 eq "NAME:"', 
        do => 'return [ $this->field_range(1, -1) ];', 
    );

Both C<$i> and C<$j> can be negative, as is allowed by the C<field()> method. So, for example:

    $parser->add_rule(
        do => 'return [ $this->field_range(-2, -1) ];'    # Saves the last two fields of every line
    );
    
If C<$j> argument is omitted or set to C<undef>, it will be treated as C<-1> and if C<$i> is omitted, it is treated as C<0>. For example the following may be used inside rules:

    $this->field_range(1);         # Returns all elements omitting the first
    $this->field_range();          # same as fields()
    $this->field_range(undef, -2); # Returns all elements omitting the last

=cut

sub field_range {
    my $self = shift;
    my (@range) = $self->__validate_index_range(@_);
    $self->_sub_field_range(@range);
}

sub __validate_index_range {
    my $self = shift;
    $self->field($_) for (@_);
    map { _pos_index( $_, $self->NF ) } __set_defaults(@_);
}

sub __set_defaults {
    my ( $i, $j ) = @_;
    $i = 0  if not defined $i;
    $j = -1 if not defined $j;
    return ( $i, $j );
}

sub _pos_index {
    my ( $ind, $nf ) = ( shift, shift );
    ( $ind < 0 ) ? $ind + $nf : $ind;
}

sub _sub_field_range {
    my ( $self, $start, $end ) = ( shift, shift, shift );
    my (@range)
        = ( $start <= $end )
        ? ( $start .. $end )
        : reverse( $end .. $start );
    map { $self->field($_) } @range;
}

=auto_split_meth join_range

This method essentially joins the return value of the C<field_range> method. It takes three arguments. The last argument is the joining string, and the first two are optional integer arguments C<$i> and C<$j> just like C<field_range> method.

    $parser->add_rule(
        do => qq(
            $this->join_range();            # Joins all fields with $" (see perlvar)
            $this->join_range(0, -1, '#');  # Joins with # separator
            $this->join_range(2);           # Joins all elements starting with index 2 to the end
                                            # with $"
            $this->join_range(1, -2);       # Joins all elements in specified range with $"
    ));
    ## The return value of the last statement in the 'do' block is saved as a record

=cut

sub join_range {
    my $self = shift;
    my $sep  = ( @_ < 3 ) ? $LIST_SEPARATOR : pop;
    join $sep, $self->field_range(@_);
}

=auto_split_meth find_field

This method finds an element matching a given criterion. The match is done by a subroutine reference passed as argument to this method. The subroutine will be called against each field on the line, until one matches or all elements have been checked. Each field will be available in the subroutine as C<$_>. Its behavior is the same as the C<first> function of L<List::Util>.

=cut

sub find_field {
    my ( $self, $sub ) = ( shift, shift );
    foreach my $e ( @{ $self->{_fields} } ) {
        local $_ = $e;
        return $e if $sub->();
    }
    return;
}

=auto_split_meth find_field_index

This is similar to the C<L<find_field|/find_field>> method above, except that it returns the index of the element instead of the element itself.

=cut

sub find_field_index {
    my ( $self, $sub ) = ( shift, shift );
    for my $i ( 0 .. $#{ $self->{_fields} } ) {
        local $_ = $self->{_fields}->[$i];
        return $i if $sub->();
    }
    return -1;
}

=auto_split_meth splice_fields

Just like Perl's built-in C<splice> function.

The offset above is a required argument and can be negative.

B<WARNING:> This is a destructive function. It I<will> remove elements just like Perl's built-in C<splice> does, and the removed will be returned. If you only want to get the elements in a specific range of indices, try the C<L<field_range|/field_range>> method instead.

=cut

sub splice_fields {
    my $self = shift;
    splice @{ $self->{_fields} }, @_;
}

=head1 SEE ALSO

=for :list
* L<List::Util>
* L<List::SomeUtils>
* L<GNU Awk program|https://www.gnu.org/software/gawk/gawk.html>

=cut

no Moose::Role;

1;
