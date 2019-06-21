
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

1;
