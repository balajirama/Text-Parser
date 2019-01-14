use strict;
use warnings;

package Text::Parser::Multiline;

# ABSTRACT: Adds multi-line support to the Text::Parser object.

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = ();
use Role::Tiny;

=head1 SYNOPSIS

To make a multi-line parser (say to parse a file with C<\> as continuation character at end of line):

    package MyMultilineParser;
    use parent 'Text::Parser';
    use Role::Tiny::With;
    use strict;
    use warnings;

    with 'Text::Parser::Multiline';

    sub multiline_type {
        return 'join_next';
    }

    sub is_line_continued {
        my $self = shift;
        my $line = shift;
        chomp $line;
        return $line =~ /\\\s*$/;
    }

    sub join_last_line {
        my $self = shift;
        my ($last, $line) = (shift, shift);
        chomp $last;
        $last =~ s/\\\s*$/ /g;
        return $last . $line;
    }

    1;

In your C<main::>

    use MyMultilineParser;
    use strict;
    use warnings;

    my $parser = MyMultilineParser->new();
    $parser->read('multiline.txt');
    print "Read:\n"
    print $parser->get_records(), "\n";

Try with the following input F<multiline.txt>:

    Garbage In.\
    Garbage Out!

When you run the above code with this file, you should get:

    Read:
    Garbage In. Garbage Out!

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
* If the current line is a continuation of a previous line, or if the current line continues to the next line
* The continuation character and how to strip it
* The method of joining the lines

The rest is taken care of by this role.

So here are the things you need to do if you have to write a multi-line text parser:

=for :list
* As usual inherit from L<Text::Parser>, never this class (C<use parent 'Text::Parser'>)
* Compose this role into your derived class
* Implement your C<save_record> method as described in L<Text::Parser> as if you always get joined lines, and
* Implement the following methods: C<multiline_type>, C<join_last_line>, and C<is_line_continued>

In fact, you may not have to implement most/any of these methods if you C<use> one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package.

=head1 REQUIRED METHODS

The following methods are required for this role to work. You can avoid having to define some/all of these methods by simply inheriting them from C<L<Text::Parser::Multiline::Typical>>, which has some default methods that you could override. If you simply inherit all the methods in C<L<Text::Parser::Multiline::Typical>> and don't override them, the resulting multi-line parser will just join all the lines of the text input into a single string. This is how the example code in the L<Synopsis|/SYNOPSIS> is working.

=head2 C<$self->E<gt>C<multiline_type()>

Takes no arguments and returns a string which must be one of:

    join_last
    join_next

If you inherit from C<L<Text::Parser::Multiline::Typical>>, the default method returns C<'join_next'>, which means that for the given text format, the line continues on the next line. You must override it if in your text format, lines continue from the previous line instead.

=head3 C<$self->E<gt>C<is_line_continued($line)>

Takes a string argument as input. Returns a boolean that indicates if the current line is continued from the previous line, or is continued on the next line (depending on the type of multi-line text format).

=head2 C<$self->E<gt>C<join_last_line($last_line, $current_line)>

Takes two string arguments. The first is the line previously read which is expected to be continued on this line. The function should return a string that has stripped any continuation characters, and joined the current line with the previous line.

=cut

requires(
    qw(save_record lines_parsed has_aborted __read_file_handle),
    qw(multiline_type join_last_line is_line_continued) );

use Exception::Class (
    'Text::Parser::Multiline::Error',
    'Text::Parser::Multiline::Error::UnexpectedEOF' => {
        isa   => 'Text::Parser::Multiline::Error',
        alias => 'throw_unexpected_eof',
    },
    'Text::Parser::Multiline::Error::UnexpectedContinuation' => {
        isa   => 'Text::Parser::Multiline::Error',
        alias => 'throw_unexpected_continuation',
    }
);

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
    my $type = $self->multiline_type();
    $save_record_proc{$type}->( $orig, $self, @_ );
}

sub __around_is_line_continued {
    my ( $orig, $self ) = ( shift, shift );
    my $type = $self->multiline_type();
    return $orig->( $self, @_ ) if $type eq 'join_next';
    __around_is_line_part_of_last( $orig, $self, @_ );
}

sub __around_is_line_part_of_last {
    my ( $orig, $self ) = ( shift, shift );
    return 0 if not $orig->( $self, @_ );
    throw_unexpected_continuation error =>
        "$_[0] has a continuation character on the first line"
        if $self->lines_parsed() == 1;
    return 1;
}

sub __after__read_file_handle {
    my $self      = shift;
    return $self->__after_at_eof() if $self->multiline_type() eq 'join_next';
    my $last_line = $self->__pop_last_line();
    $orig_save_record->( $self, $last_line ) if defined $last_line;
}

sub __after_at_eof {
    my $self      = shift;
    my $remaining = $self->__pop_last_line();
    throw_unexpected_eof error =>
        "$remaining is still waiting to be continued. Unexpected EOF at line #"
        . $self->lines_parsed()
        if defined $remaining;
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
    return undef if not exists $self->{__temp_joined_line};
    my $last_line = $self->{__temp_joined_line};
    delete $self->{__temp_joined_line};
    return $last_line;
}

1;
