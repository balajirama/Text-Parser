use warnings;
use strict;
use feature ':5.14';

package Text::Parser;

# ABSTRACT: Simplifies text parsing. Easily extensible to parse any text format.

=head1 SYNOPSIS

    use Text::Parser;

    my $parser = Text::Parser->new();
    $parser->read(shift);
    print $parser->get_records, "\n";

The above code prints the content of the file (named in the first argument) to C<STDOUT>.

    my $parser = Text::Parser->new();
    $parser->add_rule(do => 'print');
    $parser->read(shift);

This example also does the same, but whereas the earlier code prints after reading the whole file, this one prints immediately.

    my $parser = Text::Parser->new();
    $parser->add_rule(if => '$1 eq "NAME:"', do => 'return ${2+}');
    $parser->read(shift);
    for my $name ($parser->get_records) {
        # do something more complex
    }

For more complex examples see the L<manual|Text::Parser::Manual>.

=head1 OVERVIEW

The L<need|Text::Parser::Manual/MOTIVATION> for this class stems from the fact that text parsing is the most common thing that programmers do, and yet there is no lean, simple way to do it efficiently. Most programmers still write boilerplate code with a C<while> loop.

Instead C<Text::Parser> allows programmers to parse text with terse, self-explanatory L<rules|Text::Parser::Manual::ExtendedAWKSyntax>, whose structure is very similar to L<AWK|https://books.google.com/books/about/The_AWK_Programming_Language.html?id=53ueQgAACAAJ>, but extends beyond the capability of AWK. Incidentally, AWK is L<one of the ancestors of Perl|http://history.perl.org/PerlTimeline.html>! One would have expected Perl to do way better than AWK. But while you can use Perl to do what AWK already does, that is usually limited to one-liners like C<perl -lane> or even C<perl -lan script.pl> which are L<very limited|Text::Parser::Manual::ComparingWithNativePerl> in what they can do. They aren't meant for serious projects. And it seems that L<some people still prefer AWK to Perl|https://aplawrence.com/Unixart/awk-vs.perl.html>.

With C<Text::Parser>, a developer can focus on specifying a grammar and then simply C<read> the file. The C<L<read|/read>> method automatically runs each rule collecting records from the text input into an array internally. And finally C<L<get_records|/get_records>> can retrieve the records. Thus the programmer now has the power of Perl to create complex data structures, along with the elegance of AWK to parse text files. The L<manuals|Text::Parser::Manual> illustrate this with L<examples|Text::Parser::Manual::ComparingWithNativePerl>.

=head1 THINGS TO BE DONE

This package is still a work in progress. Future versions are expected to include features to:

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
enum 'Text::Parser::Types::TrimType'      => [qw(l r b n)];

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
        multiline_type  => 'join_last',
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

If it is set to a true value, each line will be split into fields, and a set of methods (a quick list L<here|/"Other methods available on auto_split">) become accessible within the C<L<save_record|/save_record>> method. These methods are documented in L<Text::Parser::AutoSplit>.

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

The name for this attribute comes from the built-in C<FS> variable in the popular L<GNU Awk program|https://www.gnu.org/software/gawk/gawk.html>.

    $parser->FS( qr/\s+\(*|\s*\)/ );

C<FS> I<can> be changed in your implementation of C<save_record>. But the changes would take effect only on the next line.

=cut

has FS => (
    is      => 'rw',
    isa     => 'RegexpRef',
    lazy    => 1,
    default => sub {qr/\s+/},
);

=attr multiline_type

If the target text format allows line-wrapping with a continuation character, the C<multiline_type> option tells the parser to join them into a single line. When setting this attribute, one must re-define L<two more methods|/"PARSING LINE-WRAPPED FILES">.

By default, the read-write C<multiline_type> attribute has a value of C<undef>, i.e., the target text format will not have wrapped lines. It can be set to either C<'join_next'> or C<'join_last'>.

    $parser->multiline_type(undef);
    $parser->multiline_type('join_next');

    my $mult = $parser->multiline_type;
    print "Parser is a multi-line parser of type: $mult" if defined $mult;

=for :list
* If the target format allows line-wrapping I<to the B<next>> line, set C<multiline_type> to C<join_next>.
* If the target format allows line-wrapping I<from the B<last>> line, set C<multiline_type> to C<join_last>.
* To "slurp" a file into a single string, set C<multiline_type> to C<join_last>. In this special case, you don't need to re-define the C<L<is_line_continued|/is_line_continued>> and C<L<join_last_line|/join_last_line>> methods.

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
    ensure_all_roles( $self, 'Text::Parser::Multiline' )
        if defined $newval;
    return $orig->( $self, $newval );
}

=head1 METHODS

These are meant to be called from the C<::main> program or within subclasses. In general, don't override them - just use them.

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
* Since any C<if> key is ignored, the C<do> key is always C<eval>uated. Multiple calls to C<BEGIN_rule> will append to the previous calls; meaning, the actions of previous calls will be included.
* The C<BEGIN> block is mainly used to initialize some variables. So by default C<dont_record> is set true. User I<can> change this and set C<dont_record> as false, thus forcing a record to be saved.

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
* Since any C<if> key is ignored, the C<do> key is always C<eval>uated. Multiple calls to C<END_rule> will append to the previous calls; meaning, the actions of previous calls will be included.
* The C<END> block is mainly used to do final processing of collected records. So by default C<dont_record> is set true. User I<can> change this and set C<dont_record> as false, thus forcing a record to be saved.

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

B<Note:> To extend the class to other text formats, override C<L<save_record|/save_record>>.

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

=head1 OVERRIDE IN SUBCLASS

The following methods should never be called in the C<::main> program. They may be overridden (or re-defined) in a subclass.

=inherit save_record

This method may be re-defined in a subclass to parse the target text format. The default implementation takes a single argument and stores it as a record. If no arguments are passed, C<undef> is stored as a record. Note that unlike earlier versions of C<Text::Parser> it is not required to override this method in your derived class. You can simply use the rules instead.

For a developer re-defining C<save_record>, in addition to C<L<this_line|/"this_line">>, six additional methods become available if the C<auto_split> attribute is set. These methods are described in greater detail in L<Text::Parser::AutoSplit>, and they are accessible only within C<save_record>.

B<Note:> Developers may store records in any form - string, array reference, hash reference, complex data structure, or an object of some class. The program that reads these records using C<L<get_records|/get_records>> has to interpret them. So developers should document the records created by their own implementation of C<save_record>.

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

=head1 USE ONLY IN RULES AND SUBCLASS

These methods return valid values only within a subclass, inside the user-implementation of methods described under L<OVERRIDE IN SUBCLASS|/"OVERRIDE IN SUBCLASS">. 

=sub_use_method this_line

Takes no arguments, and returns the current line being parsed. For example:

    sub save_record {
        # ...
        do_something($self->this_line);
        # ...
    }

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

=sub_use_method abort_reading

Takes no arguments. Returns C<1>. To be used only in the derived class to abort C<read> in the middle.

    sub save_record {
        # ...
        $self->abort_reading if some_condition($self->this_line);
        # ...
    }

=cut

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

=sub_use_method push_records

This is useful if one needs to implement an C<include>-like command in some text format. The example below illustrates this.

    package OneParser;
    use Moose;
    extends 'Text::Parser';

    my save_record {
        # ...
        # Under some condition:
        my $parser = AnotherParser->new();
        $parser->read($some_file)
        $parser->push_records($parser->get_records);
        # ...
    }

=sub_use_method Other methods available on C<auto_split>

When the C<L<auto_split|/auto_split>> attribute is on, (or if it is turned on later), the following additional methods become available:

=for :list
* L<NF|Text::Parser::AutoSplit/NF>
* L<fields|Text::Parser::AutoSplit/fields>
* L<field|Text::Parser::AutoSplit/field>
* L<field_range|Text::Parser::AutoSplit/field_range>
* L<join_range|Text::Parser::AutoSplit/join_range>
* L<find_field|Text::Parser::AutoSplit/find_field>
* L<find_field_index|Text::Parser::AutoSplit/find_field_index>
* L<splice_fields|Text::Parser::AutoSplit/splice_fields>

=method get_records

Takes no arguments. Returns an array containing all the records saved by the parser.

    foreach my $record ( $parser->get_records ) {
        $i++;
        print "Record: $i: ", $record, "\n";
    }

=method pop_record

Takes no arguments and pops the last saved record.

    my $last_rec = $parser->pop_record;
    $uc_last = uc $last_rec;
    $parser->save_record($uc_last);

=cut

has records => (
    isa        => 'ArrayRef[Any]',
    is         => 'ro',
    lazy       => 1,
    default    => sub { return []; },
    auto_deref => 1,
    init_arg   => undef,
    traits     => ['Array'],
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

=inherit PARSING LINE-WRAPPED FILES

These methods are useful when parsing line-wrapped files, i.e., if the target text format allows wrapping the content of one line into multiple lines. In such cases, you should C<extend> the C<Text::Parser> class and override the following methods.

=head3 is_line_continued

If the target text format supports line-wrapping, the developer must override and implement this method. Your method should take a string argument and return a boolean indicating if the line is continued or not.

There is a default implementation shipped with this class with return values as follows:

    multiline_type    |    Return value
    ------------------+---------------------------------
    undef             |         0
    join_last         |    0 for first line, 1 otherwise
    join_next         |         1

=cut

sub is_line_continued {
    my $self = shift;
    return 0 if not defined $self->multiline_type;
    return 0
        if $self->multiline_type eq 'join_last'
        and $self->lines_parsed() == 1;
    return 1;
}

=head3 join_last_line

Again, the developer should implement this method. This method should take two strings, join them while removing any continuation characters, and return the result. The default implementation just concatenates two strings and returns the result without removing anything (not even C<chomp>). See L<Text::Parser::Multiline> for more on this.

=cut

sub join_last_line {
    my $self = shift;
    my ( $last, $line ) = ( shift, shift );
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
