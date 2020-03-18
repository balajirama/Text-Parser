use warnings;
use strict;
use feature ':5.14';

package Text::Parser;

# ABSTRACT: Simplifies text parsing. Easily extensible to parse any text format.

=head1 SYNOPSIS

The following prints the content of the file (named in the first argument) to C<STDOUT>.

    use Text::Parser;

    my $parser = Text::Parser->new();
    $parser->read(shift);
    print $parser->get_records, "\n";

The earlier code prints after reading the whole file, this one prints immediately. Also, the third line there allows this program to read from a file name specified on command-line, or C<STDIN>. In effect, this makes this Perl code a good replica of the UNIX C<cat>.

    my $parser = Text::Parser->new();
    $parser->add_rule(do => 'print', dont_record => 1);
    ($#ARGV > 0) ? $parser->filename(shift) : $parser->filehandle(\*STDIN);
    $parser->read();       # Runs the rule for each line of input file

Here is an example with a simple rule that extracts the first error in the logfile and aborts reading further:

    my $parser = Text::Parser->new();
    $parser->add_rule(
        if => '$1 eq "ERROR:"',
            # $1 is a positional identifier for first field on the line
        do => '$this->abort_reading; return $_;'
            # $this is copy of $parser accessible from within the rule
            # abort_reading() tells parser to stop reading further
            # Returned values are saved as records. Any data structure can be saved.
            # $_ contains the full line as string, including any whitespaces
    );
    
    # Reads all lines until it encounters "ERROR:"
    $parser->read('/path/to/logfile');

    # Print a message if ...
    print "Some errors were found:\n" if $parser->get_records();

Much more complex file-formats can be read and contents stored in a data-structure:

    use strict;
    use warnings;

    package ComplexFormatParser;
    
    use Text::Parser::RuleSpec;  ## provides applies_rule + other sugar, imports Moose
    extends 'Text::Parser';

    # This rule ignores all comments
    applies_rule ignore_comments => (
        if          => 'substr($1, 0, 1) eq "#"', 
        dont_record => 1, 
    );

    # An attribute of the parser class. 
    has current_section => (
        is         => 'rw', 
        isa        => 'Str', 
        default    => undef, 
    );

    applies_rule get_header => (
        if          => '$1 eq "SECTION"', 
        do          => '$this->current_section($2);',  # $this : this parser object
        dont_record => 1, 
    );

    # ... More can be done

    package main;
    use ComplexFormatParser;

    my $p = ComplexFormatParser->new();
    $p->read('myfile.complex.fmt');

=head1 RATIONALTE

The L<motivation|Text::Parser::Manual/MOTIVATION> for this class stems from the fact that text parsing is the most common thing that programmers do, and yet there is no lean, simple way to do it efficiently. Most programmers still write boilerplate code with a C<while> loop.

Instead C<Text::Parser> allows programmers to parse text with simple, self-explanatory L<rules|Text::Parser::Manual::ExtendedAWKSyntax>, whose structure is very similar to L<AWK|https://books.google.com/books/about/The_AWK_Programming_Language.html?id=53ueQgAACAAJ>, but extends beyond the capability of AWK.

I<B<Sidenote:>> Incidentally, AWK is L<one of the ancestors of Perl|http://history.perl.org/PerlTimeline.html>! One would have expected Perl to do way better than AWK. But while you can use Perl to do what AWK already does, that is usually limited to one-liners like C<perl -lane>. Even C<perl -lan script.pl> is not meant for serious projects. And it seems that L<some people still prefer AWK to Perl|https://aplawrence.com/Unixart/awk-vs.perl.html>. This is not looking good.

=head1 OVERVIEW

With C<Text::Parser>, you focus on just specifying a grammar in intuitive rules. C<Text::Parser> handles the rest. The C<L<read|/read>> method automatically runs the rules for each line, collecting records from the text input into an internal array. And then, you may use C<L<get_records|/get_records>> to retrieve the records.

Since C<Text::Parser> is a class, you may subclass it to parse very complex file formats. L<Text::Parser::RuleSpec> provides intuitive syntax sugar to specify rules in a subclass. Use of L<Moose> is encouraged. Data from parsed files can be turned into very complex data-structures or even objects.

With B<L<Text::Parser>> you have the power of Perl combined with the elegance of AWK.

=head1 THINGS TO DO FURTHER

Future versions are expected to include features to:

=for :list
* read and parse from a buffer
* automatically uncompress input
* I<suggestions welcome ...>

Contributions and suggestions are welcome and properly acknowledged.

=cut

use Moose;
use MooseX::CoverableModifiers;
use MooseX::StrictConstructor;
use namespace::autoclean;
use Moose::Util 'apply_all_roles', 'ensure_all_roles';
use Moose::Util::TypeConstraints;
use String::Util qw(trim ltrim rtrim eqq);
use Text::Parser::Errors;
use Text::Parser::Rule;
use Text::Parser::RuleSpec;

enum 'Text::Parser::Types::MultilineType' => [qw(join_next join_last)];
enum 'Text::Parser::Types::LineWrapStyle' =>
    [qw(trailing_backslash spice just_next_line slurp custom)];
enum 'Text::Parser::Types::TrimType' => [qw(l r b n)];

no Moose::Util::TypeConstraints;
use FileHandle;

has _origclass => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => '',
);

=constr new

Takes optional attributes as in example below. See section L<ATTRIBUTES|/ATTRIBUTES> for a list of the attributes and their description.

    my $parser = Text::Parser->new(
        auto_chomp      => 0,
        line_wrap       => 'just_next_line',
        auto_trim       => 'b',
        auto_split      => 1,
        FS              => qr/\s+/,
    );

=cut

around BUILDARGS => sub {
    my ( $orig, $class ) = ( shift, shift );
    return $class->$orig( @_, _origclass => $class ) if @_ > 1 or not @_;
    my $ptr = shift;
    die single_params_to_new_must_be_hash_ref() if ref($ptr) ne 'HASH';
    $class->$orig( %{$ptr}, _origclass => $class );
};

sub BUILD {
    my $self = shift;
    $self->_collect_any_class_rules;
    ensure_all_roles $self, 'Text::Parser::AutoSplit' if $self->auto_split;
    return if not defined $self->multiline_type;
    ensure_all_roles $self, 'Text::Parser::Multiline';
}

sub _collect_any_class_rules {
    my $self = shift;
    my $cls  = $self->_origclass;
    my $h    = Text::Parser::RuleSpec->_class_rule_order;
    return if not exists $h->{$cls};
    $self->_find_class_rules_and_set_auto_split( $h, $cls );
}

sub _find_class_rules_and_set_auto_split {
    my ( $self, $h, $cls ) = ( shift, shift, shift );
    my (@r)
        = map { Text::Parser::RuleSpec->_get_rule($_); } ( @{ $h->{$cls} } );
    $self->_class_rules( \@r );
    $self->auto_split(1) if not $self->auto_split;
}

=head1 ATTRIBUTES

The attributes below can be used as options to the C<new> constructor. Each attribute has an accessor with the same name.

=attr auto_chomp

Read-write attribute. Takes a boolean value as parameter. Defaults to C<0>.

    print "Parser will chomp lines automatically\n" if $parser->auto_chomp;

=cut

has auto_chomp => (
    is      => 'rw',
    isa     => 'Bool',
    lazy    => 1,
    default => 0,
);

=attr auto_split

Read-write boolean attribute. Defaults to C<0> (false). Indicates if the parser will automatically split every line into fields.

If it is set to a true value, each line will be split into fields, and L<a set of methods|/"USE ONLY IN RULES AND SUBCLASS"> become accessible to C<L<save_record|/save_record>> or the rules.

=cut

has auto_split => (
    is      => 'rw',
    isa     => 'Bool',
    lazy    => 1,
    default => 0,
    trigger => \&__newval_auto_split,
);

sub __newval_auto_split {
    my ( $self, $newval, $oldval ) = ( shift, shift, shift );
    ensure_all_roles $self, 'Text::Parser::AutoSplit' if $newval;
    $self->_clear_all_fields if not $newval and $oldval;
}

=attr auto_trim

Read-write attribute. The values this can take are shown under the C<L<new|/new>> constructor also. Defaults to C<'n'> (neither side spaces will be trimmed).

    $parser->auto_trim('l');       # 'l' (left), 'r' (right), 'b' (both), 'n' (neither) (Default)

=cut

has auto_trim => (
    is      => 'rw',
    isa     => 'Text::Parser::Types::TrimType',
    lazy    => 1,
    default => 'n',
);

=attr FS

Read-write attribute that can be used to specify the field separator to be used by the C<auto_split> feature. It must be a regular expression reference enclosed in the C<qr> function, like C<qr/\s+|[,]/> which will split across either spaces or commas. The default value for this argument is C<qr/\s+/>.

The name for this attribute comes from the built-in C<FS> variable in the popular L<GNU Awk program|https://www.gnu.org/software/gawk/gawk.html>. The ability to use a regular expression is an upgrade from AWK.

    $parser->FS( qr/\s+\(*|\s*\)/ );

C<FS> I<can> be changed. Changes can be made even within a rule, but it would take effect only on the next line.

=cut

has FS => (
    is      => 'rw',
    isa     => 'RegexpRef',
    lazy    => 1,
    default => sub {qr/\s+/},
);

=attr line_wrap_style

Read-write attribute used as a quick way to select from commonly known line-wrapping styles. If the target text format allows line-wrapping this attribute allows the programmer to write rules as if they were on a single line.

    $parser->line_wrap_style('trailing_backslash');

Allowed values are:

    trailing_backslash - very common style ending lines with \
                         and continuing on the next line

    spice              - used for SPICE syntax, where on the
                         + next line the (+) continues previous line

    just_next_line     - used in simple text files written to be
                         humanly-readable. New paragraphs start
                         on a new line after a blank line.

    slurp              - used to "slurp" the whole file into
                         a single line.

    custom             - user-defined style. User must specify
                         value of multiline_type and define
                         two custom unwrap routines using the
                         custom_line_unwrap_routines method
                         when custom is chosen.

When C<line_wrap_style> is set to one of these values, the value of C<multiline_type> is automatically set to an appropriate value. Read more about L<handling the common line-wrapping styles|/"Common line-wrapping styles">.

=cut

has line_wrap_style => (
    is      => 'rw',
    isa     => 'Text::Parser::Types::LineWrapStyle|Undef',
    default => undef,
    lazy    => 1,
    trigger => \&_on_line_unwrap,
);

my %MULTILINE_VAL = (
    default            => undef,
    spice              => 'join_last',
    trailing_backslash => 'join_next',
    just_next_line     => 'join_last',
    slurp              => 'join_last',
    custom             => undef,
);

sub _on_line_unwrap {
    my ( $self, $val, $oldval ) = (@_);
    return if not defined $val and not defined $oldval;
    $val = 'default' if not defined $val;
    return if $val eq 'custom' and defined $self->multiline_type;
    $self->multiline_type( $MULTILINE_VAL{$val} );
}

=attr multiline_type

Read-write attribute used mainly if the programmer wishes to specify custom line-unwrapping methods. By default, this attribute is C<undef>, i.e., the target text format will not have wrapped lines.

    $parser->line_wrap_style(custom);
    $parser->multiline_type('join_next');

    my $mult = $parser->multiline_type;
    print "Parser is a multi-line parser of type: $mult" if defined $mult;

Allowed values for C<multiline_type> are described below, but it can also be set back to C<undef>.

=for :list
* If the target format allows line-wrapping I<to the B<next>> line, set C<multiline_type> to C<join_next>.
* If the target format allows line-wrapping I<from the B<last>> line, set C<multiline_type> to C<join_last>.

To know more about how to use this, read about L<specifying custom line-unwrap routines|/"Specifying custom line-unwrap routines">.

=cut

has multiline_type => (
    is      => 'rw',
    isa     => 'Text::Parser::Types::MultilineType|Undef',
    lazy    => 1,
    default => undef,
);

around multiline_type => sub {
    my ( $orig, $self ) = ( shift, shift );
    my $oldval = $orig->($self);
    return $oldval if not @_ or eqq( $_[0], $oldval );
    return __newval_multi_line( $orig, $self, @_ );
};

sub __newval_multi_line {
    my ( $orig, $self, $newval ) = ( shift, shift, shift );
    delete $self->{records};    # Bug W/A: role cannot apply if records exists
    ensure_all_roles( $self, 'Text::Parser::Multiline' )
        if defined $newval;
    return $orig->( $self, $newval );
}

=head1 METHODS

These are meant to be called from the C<::main> program or within subclasses.

=method add_rule

Takes a hash as input. The keys of this hash must be the attributes of the L<Text::Parser::Rule> class constructor and the values should also meet the requirements of that constructor.

    $parser->add_rule(do => '', dont_record => 1);                 # Empty rule: does nothing
    $parser->add_rule(if => 'm/li/, do => 'print', dont_record);   # Prints lines with 'li'
    $parser->add_rule( do => 'uc($3)' );                           # Saves records of upper-cased third elements

Calling this method without any arguments will throw an exception. The method internally sets the C<auto_split> attribute.

=cut

has _class_rules => (
    is      => 'rw',
    isa     => 'ArrayRef[Text::Parser::Rule]',
    lazy    => 1,
    default => sub { [] },
    traits  => ['Array'],
    handles => {
        _has_no_rules => 'is_empty',
        _get_rules    => 'elements',
    },
);

has _obj_rules => (
    is      => 'rw',
    isa     => 'ArrayRef[Text::Parser::Rule]',
    lazy    => 1,
    default => sub { [] },
    traits  => ['Array'],
    handles => {
        _push_obj_rule    => 'push',
        _has_no_obj_rules => 'is_empty',
        _get_obj_rules    => 'elements',
    },
);

sub add_rule {
    my $self = shift;
    $self->auto_split(1) if not $self->auto_split;
    my $rule = Text::Parser::Rule->new(@_);
    $self->_push_obj_rule($rule);
}

=method clear_rules

Takes no arguments, returns nothing. Clears the rules that were added to the object.

    $parser->clear_rules;

This is useful to be able to re-use the parser after a C<read> call, to parse another text with another set of rules. The C<clear_rules> method does clear even the rules set up by C<L<BEGIN_rule|/BEGIN_rule>> and C<L<END_rule|/END_rule>>.

=cut

sub clear_rules {
    my $self = shift;
    $self->_obj_rules( [] );
    $self->_clear_begin_rule;
    $self->_clear_end_rule;
}

=method BEGIN_rule

Takes a hash input like C<add_rule>, but C<if> and C<continue_to_next> keys will be ignored.

    $parser->BEGIN_rule(do => '~count = 0;');

=for :list
* Since any C<if> key is ignored, the C<do> key is required. Multiple calls to C<BEGIN_rule> will append to the previous calls; meaning, the actions of previous calls will be included.
* The C<BEGIN_rule> is mainly used to initialize some variables.
* By default C<dont_record> is set true. User I<can> change this and set C<dont_record> as false, thus forcing a record to be saved even before reading the first line of text.

=cut

has _begin_rule => (
    is        => 'rw',
    isa       => 'Text::Parser::Rule',
    predicate => '_has_begin_rule',
    clearer   => '_clear_begin_rule',
);

sub BEGIN_rule {
    my $self = shift;
    $self->auto_split(1) if not $self->auto_split;
    my (%opt) = _defaults_for_begin_end(@_);
    $self->_modify_rule( '_begin_rule', %opt );
}

sub _defaults_for_begin_end {
    my (%opt) = @_;
    $opt{dont_record} = 1 if not exists $opt{dont_record};
    delete $opt{if}               if exists $opt{if};
    delete $opt{continue_to_next} if exists $opt{continue_to_next};
    return (%opt);
}

sub _modify_rule {
    my ( $self, $func, %opt ) = @_;
    my $pred = '_has' . $func;
    $self->_append_rule_lines( $func, \%opt ) if $self->$pred();
    my $rule = Text::Parser::Rule->new(%opt);
    $self->$func($rule);
}

sub _append_rule_lines {
    my ( $self, $func, $opt ) = ( shift, shift, shift );
    my $old = $self->$func();
    $opt->{do} = $old->action . $opt->{do};
}

=method END_rule

Takes a hash input like C<add_rule>, but C<if> and C<continue_to_next> keys will be ignored. Similar to C<BEGIN_rule>, but the actions in the C<END_rule> will be executed at the end of the C<read> method.

    $parser->END_rule(do => 'print ~count, "\n";');

=for :list
* Since any C<if> key is ignored, the C<do> key is required. Multiple calls to C<END_rule> will append to the previous calls; meaning, the actions of previous calls will be included.
* The C<END_rule> is mainly used to do final processing of collected records.
* By default C<dont_record> is set true. User I<can> change this and set C<dont_record> as false, thus forcing a record to be saved after the end rule is processed.

=cut

has _end_rule => (
    is        => 'rw',
    isa       => 'Text::Parser::Rule',
    predicate => '_has_end_rule',
    clearer   => '_clear_end_rule',
);

sub END_rule {
    my $self = shift;
    $self->auto_split(1) if not $self->auto_split;
    my (%opt) = _defaults_for_begin_end(@_);
    $self->_modify_rule( '_end_rule', %opt );
}

=method read

Takes a single optional argument that can be either a string containing the name of the file, or a filehandle reference (a C<GLOB>) like C<\*STDIN> or an object of the C<L<FileHandle>> class.

    $parser->read($filename);         # Read the file
    $parser->read(\*STDIN);           # Read the filehandle

The above could also be done in two steps if the developer so chooses.

    $parser->filename($filename);
    $parser->read();                  # equiv: $parser->read($filename)

    $parser->filehandle(\*STDIN);
    $parser->read();                  # equiv: $parser->read(\*STDIN)

The method returns once all records have been read, or if an exception is thrown, or if reading has been aborted with the C<L<abort_reading|/abort_reading>> method.

Any C<close> operation will be handled (even if any exception is thrown), as long as C<read> is called with a file name parameter - not if you call with a file handle or C<GLOB> parameter.

    $parser->read('myfile.txt');      # Will close file automatically

    open MYFH, "<myfile.txt" or die "Can't open file myfile.txt at ";
    $parser->read(\*MYFH);            # Will not close MYFH
    close MYFH;

=cut

sub read {
    my $self = shift;
    return if not defined $self->_handle_read_inp(@_);
    $self->_run_begin_end_block('_begin_rule');
    $self->__read_and_close_filehandle;
    $self->_run_begin_end_block('_end_rule');
    $self->_ExAWK_symbol_table( {} );
}

sub _handle_read_inp {
    my $self = shift;
    return $self->filehandle   if not @_;
    return                     if not ref( $_[0] ) and not $_[0];
    return $self->filename(@_) if not ref( $_[0] );
    return $self->filehandle(@_);
}

has _ExAWK_symbol_table => (
    is      => 'rw',
    isa     => 'HashRef[Any]',
    default => sub { {} },
    lazy    => 1,
);

sub _run_begin_end_block {
    my ( $self, $func ) = ( shift, shift );
    my $pred = '_has' . $func;
    return if not $self->$pred();
    my $rule = $self->$func();
    $rule->_run( $self, 0 );
}

sub __read_and_close_filehandle {
    my $self = shift;
    $self->_prep_to_read_file;
    $self->__read_file_handle;
    $self->_close_filehandles if $self->_has_filename;
    $self->_clear_this_line;
}

sub _prep_to_read_file {
    my $self = shift;
    $self->_reset_line_count;
    $self->_empty_records;
    $self->_clear_abort;
}

sub __read_file_handle {
    my $self = shift;
    my $fh   = $self->filehandle();
    while (<$fh>) {
        last if not $self->__parse_line($_);
    }
}

sub __parse_line {
    my ( $self, $line ) = ( shift, shift );
    $self->_next_line_parsed();
    $line = $self->_def_line_manip($line);
    $self->_set_this_line($line);
    $self->save_record($line);
    return not $self->has_aborted;
}

sub _def_line_manip {
    my ( $self, $line ) = ( shift, shift );
    chomp $line if $self->auto_chomp;
    return $self->_trim_line($line);
}

sub _trim_line {
    my ( $self, $line ) = ( shift, shift );
    return $line        if $self->auto_trim eq 'n';
    return trim($line)  if $self->auto_trim eq 'b';
    return ltrim($line) if $self->auto_trim eq 'l';
    return rtrim($line);
}

=method filename

Takes an optional string argument containing the name of a file. Returns the name of the file that was last opened if any. Returns C<undef> if no file has been opened.

    print "Last read ", $parser->filename, "\n";

The value stored is "persistent" - meaning that the method remembers the last file that was C<L<read|/read>>.

    $parser->read(shift @ARGV);
    print $parser->filename(), ":\n",
          "=" x (length($parser->filename())+1),
          "\n",
          $parser->get_records(),
          "\n";

A C<read> call with a filehandle, will clear the last file name.

    $parser->read(\*MYFH);
    print "Last file name is lost\n" if not defined $parser->filename();

=cut

has filename => (
    is        => 'rw',
    isa       => 'Str|Undef',
    lazy      => 1,
    init_arg  => undef,
    default   => undef,
    predicate => '_has_filename',
    clearer   => '_clear_filename',
    trigger   => \&_set_filehandle,
);

sub _set_filehandle {
    my $self = shift;
    return $self->_clear_filename if not defined $self->filename;
    $self->_save_filehandle( $self->__get_valid_fh );
}

sub __get_valid_fh {
    my $self  = shift;
    my $fname = $self->_get_valid_text_filename;
    return FileHandle->new( $fname, 'r' ) if defined $fname;
    $fname = $self->filename;
    $self->_clear_filename;
    $self->_throw_invalid_file_exception($fname);
}

# Don't touch: Override this in Text::Parser::AutoUncompress
sub _get_valid_text_filename {
    my $self  = shift;
    my $fname = $self->filename;
    return $fname if -f $fname and -r $fname and -T $fname;
    return;
}

# Don't touch: Override this is Text::Parser::AutoUncompress
sub _throw_invalid_file_exception {
    my ( $self, $fname ) = ( shift, shift );
    die invalid_filename( name => $fname )  if not -f $fname;
    die file_not_readable( name => $fname ) if not -r $fname;
    die file_not_plain_text( name => $fname );
}

=method filehandle

Takes an optional argument, that is a filehandle C<GLOB> (such as C<\*STDIN>) or an object of the C<FileHandle> class. Returns the filehandle last saved, or C<undef> if none was saved.

    my $fh = $parser->filehandle();

Like C<L<filename|/filename>>, C<filehandle> is also "persistent". Its old value is lost when either C<filename> is set, or C<read> is called with a filename.

    $parser->read(\*STDOUT);
    my $lastfh = $parser->filehandle();          # Will return glob of STDOUT
    
=cut

has filehandle => (
    is        => 'rw',
    isa       => 'FileHandle|Undef',
    lazy      => 1,
    init_arg  => undef,
    default   => undef,
    predicate => '_has_filehandle',
    writer    => '_save_filehandle',
    reader    => '_get_filehandle',
    clearer   => '_close_filehandles',
);

sub filehandle {
    my $self = shift;
    return                      if not @_ and not $self->_has_filehandle;
    $self->_save_filehandle(@_) if @_;
    $self->_clear_filename      if @_;
    return $self->_get_filehandle;
}

=method lines_parsed

Takes no arguments. Returns the number of lines last parsed. Every call to C<read>, causes the value to be auto-reset.

    print $parser->lines_parsed, " lines were parsed\n";

=cut

has lines_parsed => (
    is       => 'ro',
    isa      => 'Int',
    lazy     => 1,
    init_arg => undef,
    default  => 0,
    traits   => ['Counter'],
    handles  => {
        _next_line_parsed => 'inc',
        _reset_line_count => 'reset',
    }
);

=method push_records

Takes an array as input, and stores each element as a separate record. Returns the number of elements in the new array.

    $parser->push_records(qw(insert these as separate records));

=method get_records

Takes no arguments. Returns an array containing all the records saved by the parser.

    foreach my $record ( $parser->get_records ) {
        $i++;
        print "Record: $i: ", $record, "\n";
    }

=method pop_record

Takes no arguments and pops the last saved record.

    my $last_rec = $parser->pop_record;

=cut

has records => (
    isa        => 'ArrayRef[Any]',
    is         => 'ro',
    lazy       => 1,
    default    => sub { return []; },
    auto_deref => 1,
    init_arg   => undef,
    traits     => ['Array'],
    predicate  => '_has_records_attrib',
    handles    => {
        get_records    => 'elements',
        push_records   => 'push',
        pop_record     => 'pop',
        _empty_records => 'clear',
        _num_records   => 'count',
        _access_record => 'accessor',
    },
);

=method last_record

Takes no arguments and returns the last saved record. Leaves the saved records untouched.

    my $last_rec = $parser->last_record;

=cut

sub last_record {
    my $self  = shift;
    my $count = $self->_num_records();
    return if not $count;
    return $self->_access_record( $count - 1 );
}

=method has_aborted

Takes no arguments, returns a boolean to indicate if text reading was aborted in the middle.

    print "Aborted\n" if $parser->has_aborted();

=cut

has abort => (
    is      => 'rw',
    isa     => 'Bool',
    lazy    => 1,
    default => 0,
    traits  => ['Bool'],
    reader  => 'has_aborted',
    handles => {
        abort_reading => 'set',
        _clear_abort  => 'unset'
    },
);

=method custom_line_unwrap_routines

This method should be used only when the line-wrapping supported by the text format is not already among the L<known line-wrapping styles supported|/"Common line-wrapping styles">.

Takes a hash argument with required keys C<is_wrapped> and C<unwrap_routine>. Used in setting up L<custom line-unwrapping routines|/"Specifying custom line-unwrap routines">.

Here is an example of setting custom line-unwrapping routines:

    $parser->multiline_type('join_last');
    $parser->custom_line_unwrap_routines(
        is_wrapped => sub {     # A method that detects if this line is wrapped or not
            my ($self, $this_line) = @_;
            $this_line =~ /^[~]/;
        }, 
        unwrap_routine => sub { # A method to unwrap the line by joining it with the last line
            my ($self, $last_line, $this_line) = @_;
            chomp $last_line;
            $last_line =~ s/\s*$//g;
            $this_line =~ s/^[~]\s*//g;
            "$last_line $this_line";
        }, 
    );

Now you can parse a file with the following content:

    This is a long line that is wrapped around with a custom
    ~ character - the tilde. It is unusual, but hey, we're
    ~ showing an example.

When C<$parser> gets to C<read> this, these three lines get unwrapped and processed by the rules, as if it were a single line.

L<Text::Parser::Multiline> shows another example with C<join_next> type.

=cut

has _is_wrapped => (
    is      => 'rw',
    isa     => 'CodeRef|Undef',
    default => undef,
    lazy    => 1,
);

has _unwrap_routine => (
    is      => 'rw',
    isa     => 'CodeRef|Undef',
    default => undef,
    lazy    => 1,
);

sub custom_line_unwrap_routines {
    my $self = shift;
    my ( $is_wrapped, $unwrap_routine )
        = Text::Parser::RuleSpec::_check_custom_unwrap_args(@_);
    $self->_prep_for_custom_unwrap_routines;
    $self->_is_wrapped($is_wrapped);
    $self->_unwrap_routine($unwrap_routine);
}

sub _prep_for_custom_unwrap_routines {
    my $self = shift;
    die already_set_line_wrap_style( value => $self->line_wrap_style )
        if defined $self->line_wrap_style
        and 'custom' ne $self->line_wrap_style;
    $self->line_wrap_style('custom');
}

=head1 USE ONLY IN RULES AND SUBCLASS

These methods can be used only inside rules, or methods of a subclass. Some of these methods are available only when C<auto_split> is on. They are listed as follows:

=for :list
* L<NF|Text::Parser::AutoSplit/NF> - number of fields on this line
* L<fields|Text::Parser::AutoSplit/fields> - all the fields as an array of strings ; trailing C<\n> removed
* L<field|Text::Parser::AutoSplit/field> - access individual elements of the array above ; negative arguments count from back
* L<field_range|Text::Parser::AutoSplit/field_range> - array of fields in the given range of indices ; negative arguments allowed
* L<join_range|Text::Parser::AutoSplit/join_range> - join the fields in the range of indices ; negative arguments allowed
* L<find_field|Text::Parser::AutoSplit/find_field> - returns field for which a given subroutine is true ; each field is passed to the subroutine in C<$_>
* L<find_field_index|Text::Parser::AutoSplit/find_field_index> - similar to above, except it returns the index of the field instead of the field itself
* L<splice_fields|Text::Parser::AutoSplit/splice_fields> - like the native Perl C<splice>

Other methods described below are also to be used only inside a rule, or inside methods called by the rules.

=sub_use_method abort_reading

Takes no arguments. Returns C<1>. Aborts C<read>ing any more lines, and C<read> method exits gracefully as if nothing unusual happened.

    $parser->add_rule(
        do          => '$this->abort_reading;',
        if          => '$1 eq "EOF"', 
        dont_record => 1, 
    );

=sub_use_method this_line

Takes no arguments, and returns the current line being parsed. For example:

    $parser->add_rule(
        if => 'length($this->this_line) > 256', 
    );
    ## Saves all lines longer than 256 characters

Inside rules, instead of using this method, one may also use C<$_>:

    $parser->add_rule(
        if => 'length($_) > 256', 
    );

=cut

has _current_line => (
    is       => 'ro',
    isa      => 'Str|Undef',
    init_arg => undef,
    writer   => '_set_this_line',
    reader   => 'this_line',
    clearer  => '_clear_this_line',
    default  => undef,
);

=head1 HANDLING LINE-WRAPPING

Different text formats sometimes allow line-wrapping to make their content more human-readable. Handling this can be rather complicated if you use native Perl, but extremely easy with L<Text::Parser>.

=head2 Common line-wrapping styles

L<Text::Parser> supports a range of commonly-used line-unwrapping routines which can be selected using the C<L<line_wrap_style|Text::Parser/"line_wrap_style">> attribute. The attribute automatically sets up the parser to handle line-unwrapping for that specific text format.

    $parser->line_wrap_style('trailing_backslash');
    # Now when read runs the rules, all the back-slash
    # line-wrapped lines are auto-unwrapped to a single
    # line, and rules are applied on that single line

When C<read> reads each line of text, it looks for any trailing backslash and unwraps the line. The next line may have a trailing back-slash too, and that too is unwrapped. Once the fully-unwrapped line has been identified, the rules are run on that unwrapped line, as if the file had no line-wrapping at all. So say the content of a line is like this:

    This is a long line wrapped into multiple lines \
    with a back-slash character. This is a very common \
    way to wrap long lines. In general, line-wrapping \
    can be much easier on the reader's eyes.

When C<read> runs any rules in C<$parser>, the text above appears as a single line in C<$_> to each rule in C<$parser>.

=cut

=head2 Specifying custom line-unwrap routines

I have included the common types of line-wrapping styles known to me. But obviously there can be more. To specify a custom line-unwrapping style follow these steps:

=for :list
* Set the C<L<multiline_type|/"multiline_type">> attribute appropriately. If you do not set this, your custom unwrapping routines won't have any effect.
* Call C<L<custom_line_unwrap_routines|/"custom_line_unwrap_routines">> method. If you forget to call this method, or if you don't provide appropriate arguments, then an exception is thrown.

L<Here|/"custom_line_unwrap_routines"> is an example with C<join_last> value for C<multiline_type>. And L<here|Text::Parser::Multiline/"SYNOPSIS"> is an example using C<join_next>. You'll notice that in both examples, you need to specify both routines. In fact, if you don't 

=cut

=head2 Line-unwrapping in a subclass

You may subclass C<Text::Paser> to parse your specific text format. And that format may support some line-wrapping. To handle the known common line-wrapping styles, set a default value for C<line_wrap_style>. For example: 

    package MyParser;

    use Text::Parser::RuleSpec;
    extends 'Text::Parser';

    has '+line_wrap_style' => ( default => 'slurp', is => 'ro');
    has '+multiline_type'  => ( is => 'ro' );

Of course, you don't I<have> to make them read-only.

To setup custom line-unwrapping routines in a subclass, you can use the C<L<unwraps_lines_using|Text::Parser::RuleSpec/"unwraps_lines_using">> syntax sugar from L<Text::Parser::RuleSpec>. For example:

    package MyParser;

    use Text::Parser::RuleSpec;
    extends 'Text::Parser';

    has '+multiline_type' => (
        default => 'join_next',
        is => 'ro', 
    );

    unwraps_lines_using(
        is_wrapped     => \&_my_is_wrapped_routine, 
        unwrap_routine => \&_my_unwrap_routine, 
    );

=head1 OVERRIDE IN SUBCLASS

The following methods should never be called in the C<::main> program. They may be overridden (or re-defined) in a subclass. For the most part, one would never have to override any of these methods at all. But just in case someone wants to...

=inherit save_record

The default implementation takes a single argument, runs any rules, and saves the returned value as a record in an internal array. If nothing is returned from the rule, C<undef> is stored as a record.

B<Note>: Starting C<0.925> version of C<Text::Parser> it is not required to override this method in your derived class. In most cases, you should use the rules.

=cut

sub save_record {
    my ( $self, $record ) = ( shift, shift );
    ( $self->_has_no_rules and $self->_has_no_obj_rules )
        ? $self->push_records($record)
        : $self->_run_through_rules;
}

sub _run_through_rules {
    my $self = shift;
    foreach my $rule ( $self->_get_rules, $self->_get_obj_rules ) {
        next if not $rule->_test($self);
        $rule->_run( $self, 0 );
        last if not $rule->continue_to_next;
    }
}

=inherit is_line_continued

The default implementation of this routine:

    multiline_type    |    Return value
    ------------------+---------------------------------
    undef             |         0
    join_last         |    0 for first line, 1 otherwise
    join_next         |         1

In earlier versions of L<Text::Parser> you had no way but to subclass L<Text::Parser> to change the routine that detects if a line is wrapped. Now you can instead select from a list of known C<line_wrap_style>s, or even set custom methods for this.

=inherit join_last_line

The default implementation of this routine takes two string arguments, joins them without any C<chomp> or any other operation, and returns that result.

In earlier versions of L<Text::Parser> you had no way but to subclass L<Text::Parser> to select a line-unwrapping routine. Now you can instead select from a list of known C<line_wrap_style>s, or even set custom methods for this.

=cut

my %IS_LINE_CONTINUED = (
    default            => \&_def_is_line_continued,
    spice              => \&_spice_is_line_contd,
    trailing_backslash => \&_tbs_is_line_contd,
    just_next_line     => \&_jnl_is_line_contd,
    slurp              => \&_def_is_line_continued,
    custom             => undef,
);

my %JOIN_LAST_LINE = (
    default            => \&_def_join_last_line,
    spice              => \&_spice_join_last_line,
    trailing_backslash => \&_tbs_join_last_line,
    just_next_line     => \&_jnl_join_last_line,
    slurp              => \&_def_join_last_line,
    custom             => undef,
);

sub is_line_continued {
    my $self = shift;
    return 0 if not defined $self->multiline_type;
    my $routine = $self->_get_is_line_contd_routine;
    die undef_line_unwrap_routine( name => 'is_wrapped' )
        if not defined $routine;
    $routine->( $self, @_ );
}

sub _val_of_line_wrap_style {
    my $self = shift;
    defined $self->line_wrap_style ? $self->line_wrap_style : 'default';
}

sub _get_is_line_contd_routine {
    my $self = shift;
    my $val  = $self->_val_of_line_wrap_style;
    ( $val ne 'custom' )
        ? $IS_LINE_CONTINUED{$val}
        : $self->_is_wrapped;
}

sub join_last_line {
    my $self    = shift;
    my $routine = $self->_get_join_last_line_routine;
    die undef_line_unwrap_routine( name => 'unwrap_routine' )
        if not defined $routine;
    $routine->( $self, @_ );
}

sub _get_join_last_line_routine {
    my $self = shift;
    my $val  = $self->_val_of_line_wrap_style;
    ( $val ne 'custom' )
        ? $JOIN_LAST_LINE{$val}
        : $self->_unwrap_routine;
}

sub _def_is_line_continued {
    my $self = shift;
    return 0
        if $self->multiline_type eq 'join_last'
        and $self->lines_parsed() == 1;
    return 1;
}

sub _spice_is_line_contd {
    my $self = shift;
    substr( shift, 0, 1 ) eq '+';
}

sub _tbs_is_line_contd {
    my $self = shift;
    substr( trim(shift), -1, 1 ) eq "\\";
}

sub _jnl_is_line_contd {
    my $self = shift;
    return 0 if $self->lines_parsed == 1;
    return length( trim(shift) ) > 0;
}

sub _def_join_last_line {
    my ( $self, $last, $line ) = ( shift, shift, shift );
    return $last . $line;
}

sub _spice_join_last_line {
    my ( $self, $last, $line ) = ( shift, shift, shift );
    chomp $last;
    $line =~ s/^[+]\s*/ /;
    $last . $line;
}

sub _tbs_join_last_line {
    my ( $self, $last, $line ) = ( shift, shift, shift );
    chomp $last;
    $last =~ s/\\\s*$//;
    rtrim($last) . ' ' . ltrim($line);
}

sub _jnl_join_last_line {
    my ( $self, $last, $line ) = ( shift, shift, shift );
    chomp $last;
    return $last . $line;
}

=head1 EXAMPLES

You can find example code in L<Text::Parser::Manual::ComparingWithNativePerl>.

=head1 SEE ALSO

=for :list
* L<Text::Parser::Manual> - Read this manual
* L<The AWK Programming Language|https://books.google.com/books/about/The_AWK_Programming_Language.html?id=53ueQgAACAAJ> - by B<A>ho, B<W>einberg, and B<K>ernighan.
* L<Text::Parser::Errors> - documentation of the exceptions this class throws
* L<Text::Parser::Multiline> - how to read line-wrapped text input

=cut

__PACKAGE__->meta->make_immutable;

no Moose;

1;
