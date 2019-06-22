
use strict;
use warnings;

package Text::Parser::RuleSpec;

# ABSTRACT: specifying class rules for a Text::Parser

=head1 SYNOPSIS

This class is primarily to enable users to make sub-classes of C<Text::Parser> in such a way that the rules can be easily re-used.

    package Parser1;

    use Text::Parser::RuleSpec;
    extends 'Text::Parser';

    new_rule 'RuleName1', if => '# condition', do => 'return $0';
    # .
    # .
    # .
    # Lots of rules
    # .
    # .
    #
    
    sub BUILD {
        my $self = shift;
        $self->class_rules(__PACKAGE__);
    }

The later...

    package Parser2;

    use Text::Parser::RuleSpec;
    extends 'Parser1';

    modify_rule 'Parser1/RuleName1', if => '# other condition', do => '# do something else';
    # .
    # .
    # .
    # Other rules special to Parser2
    # .
    # .
    #

    sub BUILD {
        my $self = shift;
        $self->class_rules(__PACKAGE__);
    }

Now in C<main>

    use Parser1;
    use Parser2;
    use strict;

    my $p1 = Parser1->new();
    my $p2 = Parser2->new();
    $p1->read('file.txt'); ## Applies rules only from Parser1
    $p2->read('file.txt'); ## Applies all rules of Parser1, except the one that is modified
                           ## and all other rules special to Parser2

=cut

use Moose;
use Moose::Exporter;
use MooseX::ClassAttribute;

Moose::Exporter->setup_import_methods(
    with_meta => ['spec_rule'],
    also      => 'Moose'
);

class_has _all_rules => (
    is      => 'rw',
    isa     => 'HashRef[Text::Parser::Rule]',
    lazy    => 1,
    default => sub { {} },
    traits  => ['Hash'],
    handles => {
        _add_new_rule => 'set',
        _exists_rule  => 'exists'
    },
);

class_has _rules_of_class => (
    is      => 'rw',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    default => sub {
        { [] }
    },
);

sub spec_rule {
    my ( $meta, $name ) = ( shift, shift );
    my $rule = Text::Parser::Rule->new(@_);
    Text::Parser::RuleSpec->_add_new_rule( $meta->name . '/' . $name, $rule );
}

__PACKAGE__->meta->make_immutable;

no Moose;
no MooseX::ClassAttribute;

1;
