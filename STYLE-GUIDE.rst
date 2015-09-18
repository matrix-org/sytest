SyTest code style guide
=======================

This document gives a guide to the syntax and some of the semantic details of
the prevailing style in SyTest. As with all style guides, it remains just a
guide. Exceptions to the rules can normally be found all over the place. While
it is highly likely that at least some of them are inadvertant, others will be
because of an overriding contextual or visual reason. Any style guide exists
primarily as an aid to the present and future readers of the code, and cases
will always exist that can be argued to be neater and more readable in spite of
a style guide rule.

Perl features
-------------

The current baseline Perl version is 5.14; avoid using language features
beyond that.

Naming
------

General Perl naming style applies::

  package Package::NamesHave::CamelCase;

  use constant CONSTANTS_ARE_SHOUTY => 1;

  my $variable_names_are_lowecase;
  our $as_are_package_vars;

Line Lengths
------------

Take care to keep any meaningful semantic content within a line before the 80th
column of the file. That is not to say that no line can be longer than this -
in such cases as error message strings, it is acceptable to spill over that
boundary provided there is no significant detail "hiding" there. The reader can
reasonably infer the presence of such items as the closing string quote and
statement-terminating semicolon or list item separating comma without needing
to see them.

Whitespace
----------

Whitespace should be used liberally, to make visual space between things that
should be considered distinct and separate. Appropriately applied spacing can
greatly help to make similar things look similar, and different things look
different by the nature of their overall "shape".

Vertical whitespace generally follows GNU C style; the open/close braces of
toplevel functions get their own lines::

  sub name_here
  {
     ...
  }

Other control structures, including inner nested anonymous functions, should
take the opening brace on the same line::

  if( COND ) {
     BODY
  }

  my $code = sub {
     BODY
  };

A blank line should separate each toplevel function, and major blocks or
stages within them. The ``@_``-unpacking statement should be first within the
function and have a blank line after it.

Indentation uses 3 spaces. Please avoid hard tab (HT, "\t") characters, as
inevitably someone's editor will show them wrong. A file lacking HT will
display consistently for all. (``set et`` in vim).

``package`` does not introduce a level of indenting on its own, because
otherwise 99% of the lines in every file would be indented. Toplevel functions
and other items start in the far lefthand edge with no leading indent.

A special exception is made of indenting the body of a multi-line anonymous
function passed as an argument to a method. Normally both the method-call
parens and the anonymous ``sub`` would imply a level of indent, but to avoid
the body becoming double-indented with respect to its surroundings, it normally
takes just one overall::

  $object->method( sub {
     BODY here                          # note a single level of indent
  })

Horizontal whitespace between operators is sprinkled fairly liberally; it is
likely easier to list the places that don't contain whitespace::

  $object->method              # either side of a deref arrow

  $a->[123], ->[$idx]          # within an integer-, bareword, string-literal
  $h->{key}, ->{"k"}, ->{$k}   #   or simple variable aggregate lookup

  if( COND ) ...               # between a flow-control keyword and the opening
  while( COND ) ...            #   paren of its controlling expression

  function( @args )            # before the opening paren of a function or
  $object->method( @args )     #   method call

  function()                   # inside the parens of a function call taking no
                               #   arguments

  @$arrayref, %$hashref        # after deref operators on simple variables

  [qw( some words here )]      # inside an anonymous array constructor
                               #   initialised by a quoted word list

  @array = ()                  # inside a pair of empty parens when syntax
  $coderef->()                 #   demands that the parens themselves be
                               #   present

Places where horizontal whitespace is found::

  $a + $b                      # either side of binary operators

  func( 1, 2, 3 )              # within function and method call parens, and
  $object->method( 4, 5, 6 )   #   after each comma

  $arrref->[ $x * $y ]         # within an aggregate lookup on a non-literal
  $href->{ "key_" . $s }       #   expression

  my ( $vars, $here ) = @_;    # after 'my' and within the parens of a list
                               #   assignment

  @{ $obj->arref_method }      # within the braces of a deref operator on a
  %{ $obj->href_method }       #   non-simple variable expression

Alignment whitespace should be added before the fat-comma of name-value pairs
used to pass a set of named arguments to a function or method, or to initalise
a hash or hash reference so that the corresponding values are vertically
aligned::

  func(
     some    => "variables",
     of      => "various",
     lengths => "here",
  );

Miscellaneous Punctuation
-------------------------

Comma-separated lists having a single item per line should end in a trailing
comma so that more items can be added without disturbing existing lines (see
the named-argument passing example above).

The final statement of a block should always end in a semicolon, even though
the language syntax doesn't strictly require it. An exception can be made in
trivially-small cases such as a constant-returning anonymous function such
as::

  sub { 1 }

Object methods used as accessors, or that perform an action that doesn't take
any arguments should entirely omit the empty parens that would otherwise
appear::

  $user->name

  $user->jump

``use`` statements should only import the set of symbols required by the code
in the file, listed by quote-words, using parens::

  use Module::Name qw( list of symbols );

Avoid the use of "deferred expression" style of ``grep`` and ``map``, as they
are too subtle and don't indicate clearly enough to the reader the deferred
nature of those expressions (and additionally don't match the style that is
available to additional helper functions provided by other modules)::

  ## AVOID THIS
  grep condition($_), $list, $of, @things
  map $_ + 1, 3, 4, 5

Instead, always surround the expression with braces::

  grep { condition($_) } $list, $of, @things
  map { $_ + 1 } 3, 4, 5

Avoid extraneous arrows in multi-level aggregate structure indexing::

  $h->{outer_key}[2]{inner_key}

Avoid string-quoting hash keys or LHS of fat-comma that could be done as a
bareword::

  my $h = { bareword_key => "here" };  say $h->{bareword_key};

Comments
--------

Try to avoid verbose commenting on simply what the code is intending to do. The
code ought to be obvious enough in what it attempts to do to not need it.

Occasionally a comment is required to draw attention to a particularly
non-obvious fact of the way a piece of code works; some internal implementation
detail that might be overlooked on skimming. The presence of a comment here
against the comparative rarity of them generally in the code should itself
alert the reader to pay extra attention by actually reading that comment.

Semantic Style
--------------

The choice between ``SMT if/unless COND`` vs ``COND and/or SMT`` can be a
subtle one. Generally the choice should fall down to whether at that point in
the code it is the test condition or the side-effecting statement that is more
important to the normal flow of the program. For example, code that checks the
validity of some condition or assumption, throwing an exception if it does not
hold should bring the condition up front. Additionally, the condition should be
written in the positive sense; it should give the desired state, and use the
``or`` operator, so that it stands alone as a precondition to the following
code::

  @array or die "Expected a non-empty array of things";

``Future``-returning functions typically end with a final statement that spans
the bulk of the function's body, comprised of a long sequence of ``->then``
method calls and other chaining techniques. In such a case it is permissable
to omit the ``return`` statement which would otherwise appear visually early-on
in the body of the function, far away from the location where the eventual
result of that returned future is determined.


SyTest Specifics
================

Each test file is lexically guarded within its own scope, and symbolically
guarded from those after it by having the symbol table reset at the end.
Therefore, be liberal with the use of extra variables at file-scope within a
test, defining extra toplevel functions, and so on. Utility functions can be
imported from other modules.

Each test itself should be careful to use the ``do``, ``check``, or both stages
as is required by the test logic.

When the ``do`` or ``check`` blocks unpack ``@_`` (which contains values from
the test environment) into some lexical variables, the name of each variable
ought to match, or at least bear some resemblance to, the name of each test
environment key being requested. A blank line of whitespace between named
parameters to the ``test`` call should also be added::

  test "...",
     requires => [qw( do_request_json room_id )],

     check => sub {
        my ( $do_request_json, $room_id ) = @_;

        ...
     };

Any test environment key that contains a "meaningful" value should have a name
not beginning with ``can_``. Any key that simply indicates that some ability
has been successfully tested for should have a name starting with ``can_``,
whose value is simply ``1``.

When specifying the requirements and unpacking arguments, all the ``can_`` keys
should be listed last, ideally on a line of their own such that new value keys
can be added after the existing ones. The values of ``can_`` keys are useless
to the test code and should not be unpacked, again leaving space to add more
values later.

If a test environment key provides an arrayref of values that the test wishes
to use individually, these should be unpacked immediately after the ``@_``
line, so it is clear upfront at the top of the function what arguments it is
acting on::

  test "title here",
     requires => [qw(
        a_thing more_things
        can_do_an_action
     )],

     do => sub {
        my ( $a_thing, $more_things ) = @_;
        my ( $first_thing, $second_thing ) = @$more_things;

        ...
     };

As any ``do`` or ``check`` block is expected to return a ``Future`` instance,
as are the bodies of most ``Future`` chaining or composition methods, it is
sometimes necessary to return a dummy value when there's nothing else more
interesting::

  do => sub {
     something_simple();

     Future->done(1);
  };

This is a situation in which it is acceptable to omit the parens around the
method call, as this becomes an "atomically" recognisable pattern, reused in
many situations.
