use warnings;
use strict;

package Text::Parser;

# ABSTRACT: an extensible Perl class to parse any text file by specifying grammar in derived classes. This module supersedes the older and now defunct C<TextFileParser>.

use Exporter 'import';
our (@EXPORT_OK) = ();
our (@EXPORT)    = (@EXPORT_OK);

=head1 SYNOPSIS

    use Text::Parser;

    my $parser = Text::Parser->new();
    $parser->read(shift @ARGV);
    print $parser->get_records, "\n";

The above code reads a text file and prints the content to C<STDOUT>.

=head1 DESCRIPTION

This class can be used to parse any arbitrary text file format.

C<Text::Parser> does all operations like C<open> file, C<close> file, line-count, and storage/deletion/retrieval of records. Future versions are expected to include progress-bar support. All these software features are file-format independent and can be re-used in parsing any text file format. Thus derived classes of C<Text::Parser> will be able to take advantage of these features without having to re-write the code again.

The L<Examples|/"EXAMPLES"> section describes how one could use inheritance to build a parser.

=head1 EXAMPLES

The following examples should illustrate the use of inheritance to parse various types of text file formats.

=head2 Basic principle

Derived classes simply need to override one method : C<save_record>. With the help of that any arbitrary file format can be read. C<save_record> should interpret the format of the text and store it in some form by calling C<SUPER::save_record>. The C<main::> program will then use the records and create an appropriate data structure with it.

=head2 Example 1 : A simple CSV Parser

We will write a parser for a simple CSV file that reads each line and stores the records as array references.

    package Text::Parser::CSV;
    use parent 'Text::Parser';

    sub save_record {
        my ($self, $line) = @_;
        chomp $line;
        my (@fields) = split /,/, $line;
        $self->SUPER::save_record(\@fields);
    }

That's it! Now in C<main::> you can write the following.

    use Text::Parser::CSV;
    
    my $csvp = Text::Parser::CSV->new();
    $csvp->read(shift @ARGV);

=head3 Error checking

It is easy to add any error checks using exceptions. One of the easiest ways to do this is to C<use L<Exception::Class>>.

    package Text::Parser::CSV;
    use Exception::Class (
        'Text::Parser::CSV::Error', 
        'Text::Parser::CSV::TooManyFields' => {
            isa => 'Text::Parser::CSV::Error',
        },
    );
    
    use parent 'Text::Parser';

    sub save_record {
        my ($self, $line) = @_;
        chomp $line;
        my (@fields) = split /,/, $line;
        my $self->{__csv_header} = \@fields if not scalar($self->get_records);
        Text::Parser::CSV::TooManyFields->throw(error => "Too many fields on " . $self->lines_parsed)
            if scalar(@fields) > scalar(@{$self->{__csv_header}});
        $self->SUPER::save_record(\@fields);
    }

The C<Text::Parser> class will close all filehandles automatically as soon as an exception is thrown from C<save_record>. You can then catch the exception in C<main::> by C<use>ing C<L<Try::Tiny>>.

=head2 Example 2 : Multi-line records

Many text file formats have some way to indicate line-continuation. In BASH and many other interpreted shell languages, a line continuation is indicated with a trailing back-slash (\). In SPICE syntax if a line starts with a C<'+'> character then it is to be treated as a continuation of the previous line.

To illustrate multi-line records we will write a derived class that simply joins the lines in a SPICE file and stores them as records.

    package Text::Parser::LineContinuation::Spice;
    use parent 'Text::Parser'l

    sub save_record {
        my ($self, $line) = @_;
        $line = ($line =~ /^[+]\s*/) ? $self->__combine_with_last_record($line) : $line;
        $self->SUPER::save_record( $line );
    }

    sub __combine_with_last_record {
        my ($self, $line) = @_;
        $line =~ s/^[+]\s*//;
        my $last_rec = $self->pop_record;
        chomp $last_rec;
        return $last_rec . ' ' . $line;
    }

=head3 Making roles instead

Line-continuation is a classic feature which is common to many different formats. If each syntax grammar generates a new class, one could potentially have to re-write code for line-continuation for each syntax or grammar. Instead it would be good to somehow re-use only the ability to join continued lines, but leave the actual syntax recognition to actual class that understands the syntax.

But if we separate this functionality into a class of its own line we did above with C<Text::Parser::LineContinuation::Spice>, then it gives an impression that we can now create an object of C<Text::Parser::LineContinuation::Spice>. But in reality an object of this class would have not have much functionality and is therefore limited.

This is where L<roles|Role::Tiny> are very useful.

=cut

use Exception::Class (
    'Text::Parser::Exception',
    'Text::Parser::Exception::ParsingError' => {
        isa         => 'Text::Parser::Exception',
        description => 'For all parsing errors',
        alias       => 'throw_text_parsing_error'
    },
    'Text::Parser::Exception::FileNotFound' => {
        isa         => 'Text::Parser::Exception',
        description => 'File not found',
        alias       => 'throw_file_not_found'
    },
    'Text::Parser::Exception::FileCantOpen' => {
        isa         => 'Text::Parser::Exception',
        description => 'Error opening file',
        alias       => 'throw_cant_open'
    }
);

use Try::Tiny;

=method new

Takes no arguments. Returns a blessed reference of the object.

    my $parser = Text::Parser->new();

This C<$parser> variable will be used in examples below.

=cut

sub new {
    my $pkg = shift;
    bless {}, $pkg;
}

=method read

Takes zero or one argument which could be a string containing the name of the file, or a filehandle reference or a C<GLOB> (e.g. C<\*STDIN>). Throws an exception if filename provided is either non-existent or cannot be read for any reason. Or if the argument supplied is a filehandle reference, and it happens to be opened for write instead of read, then too this method will thrown an exception.

    $parser->read($filename);

    # The above is equivalent to the following
    $parser->filename($anotherfile);
    $parser->read();

    # Or the following
    $parser->filehandle(\*STDIN);
    $parser->read();

Returns once all records have been read or if an exception is thrown for any parsing errors. This function will handle all C<open> and C<close> operations on all files even if any exception is thrown.

Once the method has successfully completed, you can parse another file. This means that your parser object is not tied to the file you parse. And when you do read a new file or input stream with this C<read> method, you will lose all the records stored from the previous read operation. So this means that if you want to read a different file with the same parser object, (unless you don't care about the last records read) you should use the C<get_records> method to retrieve all the read records before parsing a new file. So all those calls to C<read> in the example above were parsing three different files, and each successive call overwrote the records from the previous call.

    $parser->read($file1);
    my (@records) = $parser->get_records();

    $parser->read(\*STDIN);
    my (@stdin) = $parser->get_records();

B<Inheritance Recommendation:> When inheriting this class (which is what you should do if you want to write a parser for your favorite text file format), don't override this method. Override C<save_record> instead.

=cut

sub read {
    my ( $self, $input ) = @_;
    return if not $self->__is_file_known_or_opened($input);
    $self->__read_and_close_filehandle()
        if defined $self->__store_read_input($input);
}

sub __is_file_name {
    my $inp = shift;
    return 0 if not defined $inp;
    my $type = ref($inp);
    return $type eq '';
}

sub __is_file_handle {
    my $inp = shift;
    return 0 if not defined $inp;
    my $type = ref($inp);
    return $type eq 'GLOB';
}

sub __store_read_input {
    my ( $self, $input ) = @_;
    return $self->filename()         if not defined $input;
    $self->__close_file              if exists $self->{__filehandle};
    return $self->filename($input)   if __is_file_name($input);
    return $self->filehandle($input) if __is_file_handle($input);
    return undef;
}

sub __is_file_known_or_opened {
    my ( $self, $fname ) = @_;
    return 0 if not defined $fname and not exists $self->{__filehandle};
    return 0 if defined $fname and not $fname;
    return 1;
}

sub __read_and_close_filehandle {
    my $self = shift;
    delete $self->{__records} if exists $self->{__records};
    $self->__read_file_handle;
    $self->__close_file;
}

sub __read_file_handle {
    my $self = shift;
    my $fh   = $self->{__filehandle};
    $self->__init_read_fh;
    while (<$fh>) {
        $self->lines_parsed( $self->lines_parsed + 1 );
        $self->__try_to_parse($_);
    }
}

sub __init_read_fh {
    my $self = shift;
    $self->lines_parsed(0);
    $self->{__bytes_read} = 0;
}

sub __try_to_parse {
    my ( $self, $line ) = @_;
    try { $self->save_record($line); }
    catch {
        $self->__close_file;
        $_->rethrow;
    };
}

=method filename

Takes zero or one string argument containing the name of a file. Returns the name of the file that was last opened if any. Returns C<undef> if no file has been opened.

    print "Last read ", $parser->filename, "\n";

=cut

sub filename {
    my ( $self, $fname ) = @_;
    $self->__check_and_open_file($fname) if defined $fname;
    return ( exists $self->{__filename} and defined $self->{__filename} )
        ? $self->{__filename}
        : undef;
}

sub __check_and_open_file {
    my ( $self, $fname ) = @_;
    throw_file_not_found error =>
        "No such file $fname or it has no read permissions"
        if not -f $fname or not -r $fname;
    $self->__open_file($fname);
    $self->{__filename} = $fname;
}

sub __open_file {
    my ( $self, $fname ) = @_;
    $self->__close_file if exists $self->{__filehandle};
    open my $fh, "<$fname"
        or throw_cant_open error => "Error while opening file $fname";
    $self->{__filehandle} = $fh;
    $self->{__size}       = ( stat $fname )[7];
}

=method filehandle

Takes zero or one C<GLOB> argument and saves it for future a C<read> call. Returns the filehandle last saved, or C<undef> if none was saved. Remember that after a successful C<read> call, filehandles are lost.

=cut

sub filehandle {
    my ( $self, $fhref ) = @_;
    $self->__save_file_handle($fhref) if $self->__check_file_handle($fhref);
    return ( exists $self->{__filehandle} and defined $self->{__filehandle} )
        ? $self->{__filehandle}
        : undef;
}

sub __save_file_handle {
    my ( $self, $fhref ) = @_;
    $self->{__filehandle} = $$fhref;
    $self->{__size}       = ( stat $$fhref )[7];
}

sub __check_file_handle {
    my ( $self, $fhref ) = @_;
    return 0 if 'GLOB' ne ref($fhref);
    throw_file_not_found error => "The filehandle $$fhref is not readable"
        if not -r $$fhref;
    return 1;
}

=method lines_parsed

Takes no arguments. Returns the number of lines last parsed.

    print $parser->lines_parsed, " lines were parsed\n";

This is also very useful for error message generation.

=cut

sub lines_parsed {
    my $self = shift;
    return $self->{__current_line} = shift if @_;
    return ( exists $self->{__current_line} ) ? $self->{__current_line} : 0;
}

=method save_record

Takes exactly one argument which can be anything: C<SCALAR>, or C<ARRAYREF>, or C<HASHREF> or anything else meaningful. The important thing to remember is that exactly one record is saved per call. So if more than one argument are passed, everything after the first argument is ignored. And if no arguments are passed, then C<undef> is stored as a record.

In an application that uses a text parser, you will most-likely never call this method directly. It is automatically called within C<read> for each line. In this base class C<Text::Parser>, C<save_record> is simply called with a string containing the line text. Derived classes can decide to store records in a different form. See L<Inheritance examples|/"EXAMPLES"> for examples on how C<save_record> could be overridden for other text file formats.

=cut

sub save_record {
    my $self = shift;
    return if not @_;
    $self->{__records} = [] if not defined $self->{__records};
    push @{ $self->{__records} }, shift;
}

sub __close_file {
    my $self = shift;
    close $self->{__filehandle};
    delete $self->{__filehandle};
}

=method get_records

Takes no arguments. Returns an array containing all the records that were read by the parser.

    foreach my $record ( $parser->get_records ) {
        $i++;
        print "Record: $i: ", $record, "\n";
    }

=cut

sub get_records {
    my $self = shift;
    return () if not exists $self->{__records};
    return @{ $self->{__records} };
}

=method last_record

Takes no arguments and returns the last saved record. Leaves the saved records untouched.

    my $last_rec = $parser->last_record;

=cut

sub last_record {
    my $self = shift;
    return undef if not exists $self->{__records};
    my (@record) = @{ $self->{__records} };
    return $record[$#record];
}

=method pop_record

Takes no arguments and pops the last saved record.

    my $last_rec = $parser->pop_record;
    $uc_last = uc $last_rec;
    $parser->save_record($uc_last);

=cut

sub pop_record {
    my $self = shift;
    return undef if not exists $self->{__records};
    pop @{ $self->{__records} };
}

1;
