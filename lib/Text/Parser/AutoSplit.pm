use strict;
use warnings;

package Text::Parser::AutoSplit;

# ABSTRACT: A role that adds the ability to auto-split a line into fields

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = ();
use Moose::Role;
use MooseX::CoverableModifiers;

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
        'n_field_iterator' => 'natatime',
    },
);

requires 'save_record', 'field_separator';

around save_record => sub {
    my ( $orig, $self, $line ) = ( shift, shift );
    my (@flds) = split $line, $self->field_separator;
    $self->_fields( \@flds );
    $orig->( $self, $line );
};

1;
