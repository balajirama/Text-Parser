use strict;
use warnings;

package Text::Parser::Multiline;

# ABSTRACT: Adds multi-line support to the Text::Parser object.

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = ();
use Moose::Role;

=head1 SYNOPSIS

    use Text::Parser;

    my $parser = Text::Parser->new(multiline_type => 'join_last');
    $parser->read('filename.txt');
    print $parser->get_records();
    print scalar($parser->get_records()), " records were read although ",
        $parser->lines_parsed(), " lines were parsed.\n";

=head1 RATIONALE

Some text formats allow users to split a single line into multiple lines, with a continuation character in the beginning or in the end, usually to improve human readability.

This extension allows users to use the familiar C<save_record> interface to save records, as if all the multi-line text inputs were joined.

=head1 OVERVIEW

To handle these types of text formats with the native L<Text::Parser> class, the derived class would need to have a C<save_record> method that would:

=for :list
* Detect if the line is continued, and if it is, save it in a temporary location. To detect this, the developer has to implement a function named C<L<is_line_continued|Text::Parser/is_line_continued>>.
* Keep appending (or joining) any continued lines to this temporary location. For this, the developer has to implement a function named C<L<join_last_line|Text::Parser/join_last_line>>.
* Once the line continuation has stopped, create and save a data record. The developer needs to write this the same way as earlier, assuming that the text is already joined properly.

It should also look for the following error conditions (see L<Text::Parser::Errors>):

=for :list
* If the end of file is reached, and the line is expected to be still continued.
* If the first line in a text input happens to be a continuation of a previous line, that is impossible, since it is the first line

To create a multi-line text parser you need to L<determine|Text::Parser/multiline_type> if your parser is a C<'join_next'> type or a C<'join_last'> type.

=head1 METHODS TO BE IMPLEMENTED

These methods must be implemented by the developer. There are default implementations provided in L<Text::Parser> but they do nothing.

=head2 C<< $parser->is_line_continued($line) >>

Takes a string argument as input. Should return a boolean that indicates if the current line is continued. If parser is a C<'join_next'> parser, then a true value from this routine means that some data is expected to be in the I<next> line which is expected to be joined with this line. If instead the parser is C<'join_last'>, then a true value from this method would mean that the current line is a continuation from the I<previous> line, and the current line should be appended to the content of the previous line. An example implementation for a subclass would look like this:

    sub is_line_continued {
        my ($self, $line) = @_;
        chomp $line;
        $line =~ /\\\s*$/;
    }

The above example method checks if a line is being continued by using a back-slash character (C<\>).

=head2 C<< $parser->join_last_line($last_line, $current_line) >>

Takes two string arguments. The first is the line previously read which is expected to be continued on this line. You can be certain that the two strings will not be C<undef>. Your method should return a string that has stripped any continuation characters, and joined the current line with the previous line.

Here is an example implementation that joins the previous line terminated by a back-slash (C<\>) with the present line:

    sub join_last_line {
        my $self = shift;
        my ($last, $line) = (shift, shift);
        $last =~ s/\\\s*$//g;
        return "$last $line";
    }

=cut

requires(
    qw(save_record multiline_type lines_parsed __read_file_handle),
    qw(join_last_line is_line_continued _set_this_line)
);

use Exception::Class (
    'Text::Parser::Multiline::Error',
    'Text::Parser::Multiline::Error::UnexpectedContinuation' => {
        isa   => 'Text::Parser::Multiline::Error',
        alias => 'throw_unexpected_continuation',
    }
);
use Text::Parser::Errors;

around save_record       => \&__around_save_record;
around is_line_continued => \&__around_is_line_continued;
after __read_file_handle => \&__after__read_file_handle;

my $orig_save_record = sub {
    return;
};

my %save_record_proc = (
    join_last => \&__join_last_proc,
    join_next => \&__join_next_proc,
);

sub __around_save_record {
    my ( $orig, $self ) = ( shift, shift );
    $orig_save_record = $orig;
    my $type = $self->multiline_type;
    $save_record_proc{$type}->( $orig, $self, @_ );
}

sub __around_is_line_continued {
    my ( $orig, $self, $line ) = ( shift, shift, shift );
    return $orig->( $self, $line ) if $self->multiline_type eq 'join_next';
    return 0 if not $orig->( $self, $line );
    return 1 if $self->lines_parsed() > 1;
    die unexpected_cont( line => $line );
}

sub __after__read_file_handle {
    my $self = shift;
    return $self->__test_safe_eof()
        if $self->multiline_type eq 'join_next';
    $self->_set_this_line( $self->__pop_last_line );
    $orig_save_record->( $self, $self->this_line );
}

sub __test_safe_eof {
    my $self = shift;
    my $last = $self->__pop_last_line();
    return if not defined $last;
    my $lnum = $self->lines_parsed();
    die unexpected_eof( discontd => $last, line_num => $lnum );
}

sub __join_next_proc {
    my ( $orig, $self ) = ( shift, shift );
    $self->__append_last_stash(@_);
    return if $self->is_line_continued(@_);
    $self->__call_orig_save_rec($orig);
}

sub __call_orig_save_rec {
    my $self = shift;
    my $orig = shift;
    $self->_set_this_line( $self->__pop_last_line );
    $orig->( $self, $self->this_line );
}

sub __join_last_proc {
    my ( $orig, $self ) = ( shift, shift );
    return $self->__append_last_stash(@_) if $self->__more_may_join_last(@_);
    $self->__call_orig_save_rec($orig);
    $self->__append_last_stash(@_);
}

sub __more_may_join_last {
    my $self = shift;
    $self->is_line_continued(@_) or not defined $self->_joined_line;
}

has _joined_line => (
    is      => 'rw',
    isa     => 'Str|Undef',
    default => undef,
    clearer => '_delete_joined_line',
);

sub __append_last_stash {
    my ( $self, $line ) = @_;
    return $self->_joined_line($line) if not defined $self->_joined_line;
    my $joined_line = $self->join_last_line( $self->__pop_last_line, $line );
    $self->_joined_line($joined_line);
}

sub __pop_last_line {
    my $self      = shift;
    my $last_line = $self->_joined_line();
    $self->_delete_joined_line;
    return $last_line;
}

no Moose::Role;

1;
