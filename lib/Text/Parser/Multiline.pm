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

To handle these types of text formats with the native L<Text::Parser> class, the derived class would need to have a C<save_record> method that would:

=for :list
* Detect if the line is continued, and if it is, save it in a temporary location
* Keep appending (or joining) any continued lines to this temporary location
* Once the line continuation stops, then create a record and save the record with C<save_record> method

It should also look for error conditions:

=for :list
* If the end of file is reached, and a joined line is still waiting incomplete, throw an exception "unexpected EOF"
* If the first line in a text input happens to be a continuation of a previous line, that is impossible, since it is the first line ; so throw an exception

This gets further complicated by the fact that whereas some multi-line text formats have a way to indicate that the line continues I<after> the current line (like a back-slash character at the end of the line or something), and some other text formats indicate that the current line is a continuation of the I<previous> line. For example, in bash, Tcl, etc., the continuation character is C<\> (back-slash) which, if added to the end of a line of code would imply "there is more on the next line". In contrast, L<SPICE|https://bwrcs.eecs.berkeley.edu/Classes/IcBook/SPICE/> has a continuation character (C<+>) on the next line, indicating that the text on that line should be joined with the I<previous> line.

This extension allows users to use the familiar C<save_record> interface to save records, as if all the multi-line text inputs were joined.

=head1 OVERVIEW

To create a multi-line text parser you need to know:

=for :list
* L<Determine|Text::Parser/new> if your parser is a C<'join_next'> type or a C<'join_last'> type.
* Recognize if a line has a continuation pattern
* How to strip the continuation character and join with last line

=head1 REQUIRED METHODS

So here are the things you need to do if you have to write a multi-line text parser:

=for :list
* As usual inherit from L<Text::Parser>, never this class (C<use parent 'Text::Parser'>)
* Override the C<new> constructor to add C<multiline_type> option by default. Read about the option L<here|Text::Parser/new>.
* Override the C<is_line_continued> method to detect if there is a continuation character on the line.
* Override the C<join_last_line> to join the previous line and the current line after stripping any continuation characters.
* Implement your C<save_record> as if you always get joined lines!

That's it! What's more? There are some default implementations for these methods in L<Text::Parser> class already. But if you want to do any stripping of continuation characters etc., you'd want to override these in your own parser class.

=head2 C<< Text::Parser->new(%options) >>

L<Decide|Text::Parser/new> if you want to set any options like C<auto_chomp> by default. In order to get a multi-line parser, you I<must> select one of C<multiline_type> values: C<'join_next'> or C<'join_last'>.

=head2 C<< $parser->is_line_continued($line) >>

Takes a string argument as input. Returns a boolean that indicates if the current line is continued from the previous line, or is continued on the next line (depending on the type of multi-line text format). You don't need to bother about how the boolean result of this routine is interpreted. That is handled depending on the type of multi-line parser. The way the result of this function is interpreted depends on the type of multi-line parser you make. If it is a C<'join_next'> parser, then a true value from this routine means that some data is expected to be in the I<next> line which is expected to be joined with this line. If instead the parser is C<'join_last'>, then a true value from this method would mean that the current line is a continuation from the I<previous> line, and the current line should be appended to the content of the previous line.

=head2 C<< $parser->join_last_line($last_line, $current_line) >>

Takes two string arguments. The first is the line previously read which is expected to be continued on this line. You can be certain that the two strings will not be C<undef>. Your method should return a string that has stripped any continuation characters, and joined the current line with the previous line. You don't need to bother about where and how this is being saved. You also don't need to bother about where the last line is stored/coming from. The management of the last line is handled internally.

=cut

requires( qw(save_record setting lines_parsed has_aborted __read_file_handle),
    qw(join_last_line is_line_continued) );

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
    my $type = $self->setting('multiline_type');
    $save_record_proc{$type}->( $orig, $self, @_ );
}

sub __around_is_line_continued {
    my ( $orig, $self ) = ( shift, shift );
    my $type = $self->setting('multiline_type');
    return $orig->( $self, @_ ) if $type eq 'join_next';
    __around_is_line_part_of_last( $orig, $self, @_ );
}

sub __around_is_line_part_of_last {
    my ( $orig, $self ) = ( shift, shift );
    return 0 if not $orig->( $self, @_ );
    return 1 if $self->lines_parsed() > 1;
    die unexpected_cont( line => $_[0] );
}

sub __after__read_file_handle {
    my $self = shift;
    return $self->__after_at_eof()
        if $self->setting('multiline_type') eq 'join_next';
    my $last_line = $self->__pop_last_line();
    $orig_save_record->( $self, $last_line ) if defined $last_line;
}

sub __after_at_eof {
    my $self = shift;
    my $last = $self->__pop_last_line();
    return if not defined $last;
    my $lnum = $self->lines_parsed();
    die unexpected_eof( remaining => $last, line_num => $lnum );
}

sub __join_next_proc {
    my ( $orig, $self ) = ( shift, shift );
    $self->__append_last_stash(@_);
    return if $self->is_line_continued(@_);
    $orig->( $self, $self->__pop_last_line() );
}

sub __join_last_proc {
    my ( $orig, $self ) = ( shift, shift );
    return $self->__append_last_stash(@_)
        if $self->is_line_continued(@_);
    my $last_line = $self->__pop_last_line();
    $orig->( $self, $last_line ) if defined $last_line;
    $self->__save_this_line( $orig, @_ );
}

sub __save_this_line {
    my ( $self, $orig ) = ( shift, shift );
    return $self->__append_last_stash(@_)
        if not $self->has_aborted;
}

sub __append_last_stash {
    my ( $self, $line ) = @_;
    my $last_line = $self->__pop_last_line();
    $last_line = $self->__strip_append_line( $line, $last_line );
    $self->__stash_line($last_line);
}

sub __strip_append_line {
    my ( $self, $line, $last ) = ( shift, shift, shift );
    return $line if not defined $last;
    return $self->join_last_line( $last, $line );
}

sub __stash_line {
    my $self = shift;
    $self->{__temp_joined_line} = shift;
}

sub __pop_last_line {
    my $self = shift;
    return if not exists $self->{__temp_joined_line};
    my $last_line = $self->{__temp_joined_line};
    delete $self->{__temp_joined_line};
    return $last_line;
}

no Moose::Role;

1;
