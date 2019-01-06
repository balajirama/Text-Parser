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
* As usual C<use parent 'Text::Parser'>, never this class
* Compose this role into your derived class
* Implement the following methods: C<multiline_type>, C<join_last_line>, C<is_line_part_of_last>, and C<is_line_continued>
* Implement your C<save_record> method as described in L<Text::Parser> as if you always get joined lines

=cut

requires(
    qw(save_record join_last_line is_line_part_of_last is_line_continued multiline_type)
);

my %save_record_proc = (
    join_last => sub {
        my ( $orig, $self ) = ( shift, shift );
        return $self->join_last_line(@_)
            if $self->is_line_part_of_last(@_);
        $orig->( $self, $self->pop_joined_line() );
    },
    join_next => sub {
        my ( $orig, $self ) = ( shift, shift );
        $self->join_last_line(@_);
        return if $self->is_line_continued(@_);
        $orig->( $self, $self->pop_joined_line() );
    },
);

around save_record => sub {
    my ( $orig, $self ) = ( shift, shift );
    my $type = $self->multiline_type();
    $save_record_proc{$type}->( $orig, $self, @_ );
};

sub push_joined_line {
    my ( $self, $line ) = ( shift, shift );
    push @{ $self->{__temp_joined_line} }, $line;
}

sub pop_joined_line {
    my $self = shift;
    pop @{ $self->{__temp_joined_line} };
}

sub peek_joined_line {
    my $self = shift;
    my $ind  = $#{ $self->{__temp_joined_line} };
    return ${ $self->{__temp_joined_line} }[$ind];
}

sub join_last_line {
    my $self = shift;
    return if not @_ or not defined $_[0];
    my $newline = $self->pop_joined_line() . shift;
    $self->push_joined_line($newline);
}

sub is_line_part_of_last {
    return 0;
}

sub is_line_continued {
    return 1;
}

1;
