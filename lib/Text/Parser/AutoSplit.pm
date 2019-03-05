use strict;
use warnings;

package Text::Parser::AutoSplit;

# ABSTRACT: A role that adds the ability to auto-split a line into fields

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = ();
use Moose::Role;
use MooseX::CoverableModifiers;

=head1 SYNOPSIS

    package MyNewParser;

    use parent 'Text::Parser';

    sub new {
        my $pkg = shift;
        $pkg->SUPER::new(
            auto_split => 1,
            FS => qr/\s+\(*|\s*\)/,
            @_, 
        );
    }

    sub save_record {
        my $self = shift;
        return $self->abort_reading if $self->NS > 0 and $self->field(0) eq 'STOP_READING';
        $self->SUPER::save_record(@_) if $self->NS > 0 and $self->field(0) !~ /^[#]/;
    }

    package main;

    my $parser = MyNewParser->new();
    $parser->read(shift);
    print $parser->get_records(), "\n";

=head1 DESCRIPTION

C<Text::Parser::AutoSplit> is a role that gets automatically composed into an object of L<Text::Parser> if the C<auto_split> attribute is set during object construction. It is useful for writing complex parsers as derived classes of L<Text::Parser>, because one has access to the fields. The field separator is controlled by another attribute C<FS>, which can be accessed via an accessor method of the same name. When the C<auto_split> attribute is set to a true value, the object of C<Text::Parser> will be able to use methods described in this role.

=cut

has _fields => (
    is       => 'rw',
    isa      => 'ArrayRef[Str]',
    lazy     => 1,
    init_arg => undef,
    default  => sub { [] },
    traits   => ['Array'],
    handles  => {
        'NF'               => 'count',
        'field'            => 'get',
        'find_field'       => 'first',
        'find_field_index' => 'first_index',
        'splice_fields'    => 'splice',
        'line_fields'      => 'elements',
    },
);

requires 'save_record', 'FS';

around save_record => sub {
    my ( $orig, $self, $line ) = ( shift, shift, shift );
    $self->_fields( [ split $self->FS, $line ] );
    $orig->( $self, $line );
};

=head1 METHODS AVAILABLE ON AUTO-SPLIT

These methods become available when C<auto_split> attribute is true. You'll get a runtime error if you try to use them otherwise. They would be most likely used inside your own implementation of C<L<save_record|/save_record>> since the splits are done for each line.

=auto_split_meth NF

The name of this method comes from the C<NF> variable in the popular GNU Awk program. It stands for number of fields. Takes no arguments, and returns the number of fields.

    sub save_record {
        my $self = shift;
        $self->save_record(@_) if $self->NF > 0;
    }

=auto_split_meth field

Takes an integer argument and returns the field whose index is passed as argument. You can specify negative elements to start counting from the end. For example index C<-1> is the last element, C<-2> is the penultimate one, etc.

    sub save_record {
        my $self = shift;
        $self->abort if $self->field(0) eq 'END';
    }

=auto_split_meth find_field

This method finds an element matching a given criterion. The match is done by a subroutine reference passed as argument to this method. The subroutine will be called against each field on the line, until one matches or all elements have been checked. Each field will be available in the subroutine as C<$_>. Its behavior is the same as the C<first> function of L<List::Util>.

    sub save_record {
        my $self = shift;
        my $param = $self->find_field(
            sub { $_ =~ /[=]/ }
        );
    }

=auto_split_meth find_field_index

This is similar to the C<L<find_field|/find_field>> method above, except that it returns the index of the element instead of the element itself.

    sub save_record {
        my $self = shift;
        my $idx = $self->find_field_index(
            sub { $_ =~ /[=]/ }
        );
    }

=auto_split_meth splice_fields

Just like Perl's built-in C<splice> function.

    ## Inside your own save_record method ...
    $self->splice_fields($offset, $length, @values);
    $self->splice_fields($offset, $length);
    $self->splice_fields($offset);

The offset above is a required argument. It can be negative.

=auto_split_meth line_fields

Takes no argument and returns all the fields as an array.

    ## Inside your own save_record method ...
    foreach my $fld ($self->line_fields) {
        # do something ...
    }

=head1 SEE ALSO

=for :list
* L<List::Util>
* L<List::SomeUtils>

=cut

1;
