use strict;
use warnings;
 
package Text::Parser::AutoSplit;

# ABSTRACT: A role that adds the ability to auto-split a line into fields

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT) = ();
use Moose::Role;

has _fields => (
    is => 'rw', 
    isa => 'ArrayRef[Str]', 
    default => sub {[]}, 
    handles => {
        'NF' => 'count', 
        'field' => 'get', 
        'find_field' => 'first', 
        'find_field_index' => 'first_index', 
        'splice_fields' => 'splice', 
        'line_fields' => 'elements', 
        'field_iterator' => 'natatime',
        'clone_fields' => 'shallow_clone', 
    }, 
);

1;
