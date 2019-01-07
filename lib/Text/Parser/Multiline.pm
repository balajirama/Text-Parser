use strict;
use warnings;

package Text::Parser::Multiline;

# ABSTRACT: Adds multi-line support to the Text::Parser object.

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = ();
use Role::Tiny;

=head1 SYNOPSIS

To make a multi-line parser, use this role:

    package MyMultilineParser;
    use Role::Tiny::With;

    with 'Text::Parser::Multiline';

    sub is_line_part_of_last {
        return 0;
    }

    sub is_line_continued {
        return 1;
    }

    1;

Note the use of C<L<Role::Tiny>> and the C<L<with|Role::Tiny/with>> runtime subroutine. Also note that because the C<L<save_record|Text::Parser/save_record>> is not overridden here, the base class's C<save_record> is used in this case. You can of course implement your C<save_record> method for your parser.

The default multi-line parser joins all lines. The above example just joins all the lines into a single string record. So:

    use MyMultilineParser;

    my $multp = MyMultilineParser->new();
    $multp->read('file.txt');
    print $multp->get_records(), "\n";

This will print the content of C<file.txt>.

=head1 RATIONALE

Some text formats allow users to split a single line into multiple lines, with a continuation character in the beginning or in the end, usually to improve human readability.

To handle these types of text formats with the native L<Text::Parser> class, the derived class would need to have a C<save_record> method that would:

=for :list
* Detect if the line is continued, and if it is, save it in a temporary location
* Keep appending (or joining) any continued lines to this temporary location
* Once the line continuation stops, then create a record and save the record with C<save_record>
* If the end of file is reached, and a joined line is still waiting incomplete, throw an exception "unexpected EOF"

This gets further complicated by the fact that some multi-line text formats have a way to indicate that the line continues after the current line (like a character at the end of the line), and some other text formats have a way to indicate that the current line is a continuation of the previous line. For example, in bash, Tcl, etc., the continuation character is C<\> (back-slash). In L<SPICE|https://bwrcs.eecs.berkeley.edu/Classes/IcBook/SPICE/> the continuation character (C<+>) is actually on the next line, indicating that the text on that line should be joined with the previous line.

=head1 OVERVIEW

As it turns out, parsing multi-line files is not so complicated. The only things that usually change from format to format, are:

=for :list
* How to detect if the current line is a continuation or if it continues to the next line
* The continuation character itself, and
* The method of joining the lines

The rest of the algorithm is mostly the same (the only variations caused by whether the format continues on the next line or joins back the previous line). So this is exactly the sort of thing that can be composed into a role. The derived class can specify the specifics above, and the role can do the steps required to call C<save_record> with the joined line.

So here are the things you need to do if you have to write a multi-line text parser:

=for :list
* As usual inherit from L<Text::Parser>, never this class (C<use parent 'Text::Parser'>)
* Compose this role into your derived class
* Implement your C<save_record> method as described in L<Text::Parser> as if you always get joined lines, and
* Implement the following methods: C<multiline_type>, C<is_line_part_of_last>, C<at_eof>, and C<is_line_continued>

In fact, you may not have to implement most/any of these methods if you C<use> one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package.

=head1 REQUIRED METHODS

The following methods are required for this role to work. To implement them, you can use C<L<pop_joined_line|/pop_joined_line>> along with the other methods defined in L<Text::Parser>.

You can avoid having to define some/all of these methods by simply C<use>ing one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package. There are some predefined defaults for each type of multi-line parser.

=head2 C<$self->E<gt>C<multiline_type()>

Takes no arguments and returns a string which must be one of:

    join_last
    join_next

If you use one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package, here's what you get:

    Information  | Text::Parser::Multiline::JoinLast | Text::Parser::Multiline::JoinNext
    -------------|-----------------------------------|----------------------------------
    Return value | join_last                         | join_next

=head2 C<$self->E<gt>C<strip_continuation_char($line)>

Takes one string argument as input. Returns a string that has stripped any continuation characters and may be appended to any previously saved line. The output of this subroutine will be used as such:

    $last_line .= $self->strip_continuation_char($line);

If you use one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package, the default method implementation returns the input argument unchanged.

=head3 C<$self->E<gt>C<is_line_part_of_last($line)>

Takes a string argument as input. Returns a boolean that indicates if the current line is a continuation of the previous line.

If you use one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package, here's what you get:

    Information  | Text::Parser::Multiline::JoinLast | Text::Parser::Multiline::JoinNext
    -------------|-----------------------------------|----------------------------------
    Return value | 1                                 | 0

=head3 C<$self->E<gt>C<is_line_continued($line)>

Takes a string argument as input. Returns a boolean that indicates if the current line is continued from the last line.

If you use one of L<Text::Parser::Multiline::JoinLast>, or L<Text::Parser::Multiline::JoinNext> in your parser package, here's what you get:

    Information  | Text::Parser::Multiline::JoinLast | Text::Parser::Multiline::JoinNext
    -------------|-----------------------------------|----------------------------------
    Return value | 0                                 | 1

=head3 C<$self->E<gt>C<at_eof()>

Takes no arguments as input. This method is automatically called right before the C<L<read|Text::Parser/read>> method of L<Text::Parser> is about to return. Actually, it is called right after the parsing loop has ended (either because there are no more lines to parse or because C<L<abort_reading|/abort_reading>> method was called).

This method should wrap up any loose ends in the line continuation handling. If any loose ends remain after C<at_eof()>, then C<Text::Parser::Multiline> role will automatically throw an exception. For example, say your continuation character is a C<\> (back-slash) at the end of a line, and say the last line of a text file has it at the end. You did not expect this. You have an error condition, and you might want to throw an exception.

=cut

requires(
    qw(save_record __read_file_handle),
    qw(multiline_type strip_continuation_char is_line_part_of_last is_line_continued at_eof)
);

my %save_record_proc = (
    join_last => sub {
        my ( $orig, $self ) = ( shift, shift );
        return $self->__append_n_save(@_)
            if $self->is_line_part_of_last(@_);
        my $last_line = $self->pop_joined_line();
        $orig->( $self, $last_line ) if defined $last_line;
        $self->__append_n_save(@_) if not exists $self->{__abort_reading};
    },
    join_next => sub {
        my ( $orig, $self ) = ( shift, shift );
        $self->__append_n_save(@_);
        return if $self->is_line_continued(@_);
        $orig->( $self, $self->pop_joined_line() );
    },
);

use Exception::Class (
    'Parser::Text::Multiline::Error',
    'Parser::Text::Multiline::Error::UnexpectedEOF' => {
        isa   => 'Parser::Text::Multiline::Error',
        alias => 'throw_unexpected_eof',
    },
    'Parser::Text::Multiline::Error::UnexpectedContinuation' => {
        isa   => 'Parser::Text::Multiline::Error',
        alias => 'throw_unexpected_continuation',
    }
);

around save_record => sub {
    my ( $orig, $self ) = ( shift, shift );
    my $type = $self->multiline_type();
    $save_record_proc{$type}->( $orig, $self, @_ );
};

around is_line_part_of_last => sub {
    my ( $orig, $self ) = ( shift, shift );
    return 0 if not $orig->( $self, @_ );
    throw_unexpected_continuation error =>
        "$_[0] has a continuation character on the first line"
        if $self->lines_parsed() == 1;
    return 1;
};

after __read_file_handle => sub {
    my $self = shift;
    $self->at_eof();
    my $remaining = $self->pop_joined_line();
    throw_unexpected_eof error =>
        "$remaining is still waiting to be continued. Unexpected EOF at line #"
        . $self->lines_parsed()
        if defined $remaining;
};

sub __append_n_save {
    my ( $self, $line ) = @_;
    my $last_line = $self->pop_joined_line();
    $last_line = $self->__strip_append_line( $line, $last_line );
    $self->{__temp_joined_line} = $last_line;
}

sub __strip_append_line {
    my ( $self, $line, $last ) = ( shift, shift, shift );
    return $line if not defined $last;
    $last .= $self->strip_continuation_char($line);
    return $last;
}

=method pop_joined_line

Takes no arguments and returns a string containing the line formed by all the strings saved till now.

    my $last_line = $self->pop_joined_line();

=cut

sub pop_joined_line {
    my $self = shift;
    return undef if not exists $self->{__temp_joined_line};
    my $last_line = $self->{__temp_joined_line};
    delete $self->{__temp_joined_line};
    return $last_line;
}

1;
