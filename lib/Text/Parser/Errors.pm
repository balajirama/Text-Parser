package Text::Parser::Errors;
use strict;
use warnings;

use Throwable::SugarFactory;
use Scalar::Util 'looks_like_number';

# ABSTRACT: Exceptions for Text::Parser

=head1 DESCRIPTION

This document contains a manifest of all the exception classes thrown by L<Text::Parser>.

=head1 EXCEPTION CLASSES

All exceptions are derived from C<Text::Parser::Errors::GenericError>. They are all based on L<Throwable::SugarFactory> and so all the exception methods of those, such as C<L<error|Throwable::SugarFactory/error>>, C<L<namespace|Throwable::SugarFactory/namespace>>, etc., will be accessible. Read L<Exceptions> if you don't know about exceptions in Perl 5.

=cut

sub _Str {
    die "attribute must be a string"
        if not defined $_[0]
        or ref( $_[0] ) ne '';
}

sub _Num {
    die "attribute must be a number"
        if not defined $_[0]
        or not looks_like_number( $_[0] );
}

exception 'GenericError' => 'a generic error';

=head2 Input file related errors

=head3 C<Text::Parser::Errors::InvalidFilename>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> is invalid.

=head4 Attributes

=for :list
* B<name> - a string with the anticipated file name.

=cut

exception
    InvalidFilename => 'file does not exist',
    has             => [
    name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::FileNotReadable>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> has no read permissions or is unreadable for any other reason.

=head4 Attributes

=for :list
* B<name> - a string with the name of the file that could not be read

=cut

exception
    FileNotReadable => 'file is not readable',
    has             => [
    name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::FileNotPlainText>

Thrown when file name specified to C<L<read|Text::Parser/read>> or C<L<filename|Text::Parser/filename>> is not a plain text file.

=head4 Attributes

=for :list
* B<name> - a string with the name of the non-text input file
* B<mime_type> - C<undef> for now. This is reserved for future.

=cut

exception
    FileNotPlainText => 'file is not a plain text file',
    has              => [
    name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    has => [
    mime_type => (
        is      => 'ro',
        default => undef,
    ),
    ],
    extends => GenericError();

=head2 Errors during line-unwrapping

=head3 C<Text::Parser::Errors::BadCustomUnwrapCall>

Generated when user specifies wrong arguments to C<L<custom_line_unwrap_routines|Text::Parser/"custom_line_unwrap_routines">>.

=head4 Attributes

=for :list
* B<err> - a string containing the problem

=cut

exception
    BadCustomUnwrapCall =>
    'Call to custom_line_unwrap_routines was not right',
    has     => [ err => ( is => 'rw', isa => \&_Str, ), ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::AlreadySetLineWrapStyle>

Generated when C<L<line_wrap_style|Text::Parser/"line_wrap_style">> is set to a value other than C<custom> and yet, a call to C<L<custom_line_unwrap_routines|Text::Parser/"custom_line_unwrap_routines">> is made.

=head4 Attributes

=for :list
* B<value> - the value of C<line_wrap_style> attribute at the time of calling

=cut

exception
    AlreadySetLineWrapStyle =>
    'Called custom_line_unwrap_routines even though line_wrap_style is defined and not custom',
    has     => [ value => ( is => 'ro', isa => \&_Str ) ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::UndefLineUnwrapRoutine>

Generated when user forgets to set a custom line-unwrap routine, but says that the C<line_wrap_style> is C<custom>.

=head4 Attributes

=for :list
* B<name> - name of the method that was not properly defined

=cut

exception
    UndefLineUnwrapRoutine => 'Forgot to set custom line-unwrap routines?',
    has                    => [ name => ( is => 'rw', isa => \&_Str, ) ],
    extends                => GenericError();

=head3 C<Text::Parser::Errors::UnexpectedEof>

Thrown when a line continuation character indicates that the last line in the file is wrapped on to the next line.

=head4 Attributes

=for :list
* B<discontd> - a string containing the line with the continuation character.
* B<line_num> - line number at which the unexpected EOF is encountered.

=cut

exception
    UnexpectedEof => 'join_next cont. character in last line, unexpected EoF',
    has           => [
    discontd => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    has => [
    line_num => (
        is  => 'ro',
        isa => \&_Num,
    ),
    ],
    extends => GenericError();

=head3 C<Text::Parser::Errors::UnexpectedCont>

Thrown when a line continuation character on the first line indicates that it is a continuation of a previous line.

=head4 Attributes

=for :list
* B<line> - a string containing the content of the line with the unexpected continuation character.

=cut

exception
    UnexpectedCont => 'join_last cont. character on first line',
    has            => [
    line => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => GenericError();

=head2 ExAWK rule syntax related

=head3 C<Text::Parser::Errors::ExAWK>

All errors corresponding to the L<Text::Parser::Rule> class.

=cut

exception ExAWK => 'a class of errors', extends => GenericError();

=head3 C<Text::Parser::Errors::BadRuleSyntax>

Generated from L<Text::Parser::Rule> class constructor or from the accessors of C<condition>, C<action>, or the method C<add_precondition>, when the rule strings specified fail to compile properly.

=head4 Attributes

=for :list
* B<code> - the original rule string
* B<msg>  - content of C<$@> after C<eval>
* B<subroutine> - stringified form of the subroutine generated from the given C<code>.

=cut

exception
    BadRuleSyntax => 'Compilation error in reading syntax',
    has           => [
    code => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    has => [
    msg => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    has => [
    subroutine => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ],
    extends => ExAWK();

=head3 C<Text::Parser::Errors::IllegalRuleNoIfNoAct>

Generated from constructor of the L<Text::Parser::Rule> when the rule is created with neither a C<condition> nor an C<action>

=cut

exception
    IllegalRuleNoIfNoAct => 'Rule created without required components',
    extends              => ExAWK();

=head3 C<Text::Parser::Errors::IllegalRuleCont>

Generated when the rule option C<continue_to_next> of the L<Text::Parser::Rule> object is set true when C<dont_record> is false.

=cut

exception
    IllegalRuleCont =>
    'Rule cannot continue to next if action result is recorded',
    extends => ExAWK();

=head3 C<Text::Parser::Errors::RuleRunImproperly>

Generated from C<run> method of L<Text::Parser::Rule> is called without an object of L<Text::Parser> as argument.

=cut

exception
    RuleRunImproperly => 'run was called without a parser object',
    extends           => ExAWK();

=head2 Related to class rulespec

=head3 C<Text::Parser::Errors::RuleSpecError>

Base class for all RuleSpec errors, generated using the functions of L<Text::Parser::RuleSpec> incorrectly.

=cut

exception
    RuleSpecError => 'base class for errors from Text::Parser::RuleSpec',
    extends       => GenericError();

=head3 C<Text::Parser::Errors::SpecMustHaveName>

Thrown when C<L<applies_rule|Text::Parser::RuleSpec/applies_rule>> is called without a rule name.

=cut

exception
    SpecMustHaveName => 'applies_rule must be called with a name argument',
    extends          => RuleSpecError(),
    has              => [
    package_name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ];

=head3 C<Test::Parser::Errors::SpecRequiresHash>

Thrown when C<L<applies_rule|Text::Parser::RuleSpec/applies_rule>> is called with invalid number of options.

=cut

exception
    SpecRequiresHash =>
    'applies_rule must be called with required hash argument',
    extends => RuleSpecError(),
    has     => [
    rule_name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ];

=head3 C<Text::Parser::Errors::MainCantApplyRule>

This error means that C<L<applies_rule|Text::Parser::RuleSpec/applies_rule>> was called from your C<main> program (which is not right).

=cut

exception
    MainCantApplyRule => 'applies_rule was called in main',
    extends           => RuleSpecError(),
    has               => [
    rule_name => (
        is  => 'ro',
        isa => \&_Str,
    ),
    ];

=head3 C<Text::Parser::Errors::NameRuleUniquely>

If the same rule name is used in the same namespace, this error is thrown.

=cut

exception
    NameRuleUniquely => 'name rules uniquely',
    extends          => RuleSpecError();

=head2 Miscellaneous

=head3 C<Text::Parser::Errors::SingleParamsToNewMustBeHashRef>

This error is thrown in place of C<Moose::Exception::SingleParamsToNewMustBeHashRef>.

=cut

exception
    SingleParamsToNewMustBeHashRef =>
    'single argument to new() must be hashref',
    extends => GenericError();

=head1 SEE ALSO

=for :list
* L<Text::Parser>
* L<Text::Parser::Rule>
* L<Throwable::SugarFactory>
* L<Exceptions>

=cut

1;

