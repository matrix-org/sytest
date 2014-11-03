Developing
----------

``sytest`` consists of two basic parts; the core test runner program and its
associated helper modules, and a set of test scripts themselves. The overall
runner program controls startup and shutdown of a number of ``synapse``
processes by means of a helper module, and reads and executes tests specified
in each of the actual test scripts.

The test scripts are read and executed in file name order, thus giving a
reliable order to them. Individual tests within these files can declare
pre-requisites; if those dependencies are not met by the time the test is run
then it is skipped.

The test system as a whole maintains an *environment*; a set of named values
created by earlier tests that later ones can inspect and use. Tests are
executed sequentially as given in the files, allowing later tests to depend on
state set up by earlier ones. Because of this, the individual tests are **not**
independent, but must be run as an entire sequence, with later tests using
persistent state set up by earlier ones.

Tests
-----

Each file under the ``tests`` directory is run as a normal perl file, within
the context of the main program. It should contain calls to ``test`` and
``prepare``, which sequentially control the execution of all the tests and
other preparation steps that happen between them.

Each call to ``test`` takes a single positional argument giving descriptive
text to use as a caption, and a set of named arguments to control how the test
runs.

::
    test "Here is the caption of the test",
       ...

The following named arguments apply to a test. Each of them is optional, and
is described in more detail in the following sections.

  ``do``
    Provides a ``CODE`` reference (most likely in the form of an inline
    ``sub { ... }`` block) which contains the main activity of the test

  ``check``
    Provides a ``CODE`` reference similar to the ``do`` argument, which
    contains the checking code for the test

  ``requires``
    Provides an ``ARRAY`` reference giving a list of named requirements.

A call to ``provide`` is similar to ``test``, except that it doesn't take a
``check`` block, only a ``do``.

Code Blocks
-----------

The blocks of code given to ``do`` and ``check`` arguments follow the same
basic pattern. Each is given a list of arguments matching the dependencies of
the test (see below), and is expected to return a ``Future``. The
interpretation of the return value of this future depends on the type of block.

If a test provides both a ``do`` and a ``check`` block, then the checking one
is run either side of the main step code, to test that it fails before the main
code and passes afterwards. The test is considered to succeed if its ``do``
block does not fail, and its ``check`` block succeeds with a true value
afterwards. It is not specifically a failure if the ``check`` block succeeded
true before the main step was executed, but in that situation a warning is
printed.

If only one is provided then it is executed just once. In this case there is no
real distinction between ``do`` and ``check`` at presence, though stylistically
``check`` should be used for purely-passive "look-but-don't-touch" styles of
activity, in case a distinction is introduced later (for example, allowing
multiple blocks to execute concurrently).

Dependencies and Environment
----------------------------

As the tests and preparation steps are run, they can accumulate persistent
state that somehow represents the side-effects of their activity (such as
users created in servers) that later tests can use. These are stored as named
values in the *environment*, which is shared among all the tests. Individual
tests can declare that they depend on a number of named keys by giving a list
of these key names in the ``requires`` list for that test. If any of these keys
are not present, the entire test is skipped.

When a ``do`` or ``require`` block is run for a test that does have all of its
dependencies satisfied, the requested values of the test environment are passed
in as positional arguments to the code block. The code can then use these to
help it perform its activity.

Code blocks can provide new values into the test environment by using the
``provide`` function::

    provide name_of_key => $value;

By convention, environment keys that simply remark that some ability has been
proven possible without providing any significant value are given names
beginning with ``can_``, and take the value ``1``. They are requested at the
end of the ``requires`` list, after all of the significant values, so as not to
cause "holes" when unpacking the argument list.

Initial Environment
-------------------

The following environment keys are provided at the beginning by the test runner
itself:

  ``http_clients``
    An ``ARRAY`` containing a HTTP client instance per ``synapse`` home server.
    Each is of a subclass of ``Net::Async::HTTP`` that stores a URL base that
    points at the IP/port the testing home servers are running on.

  ``first_http_client``
    The first value from ``http_clients``, pointing at the first home server,
    for convenience where most of the tests run there.

Test Assertions
---------------

The following convenient helper functions are also available for test code.
Each will throw an exception if it fails; the return value does not need to be
tested.

  ``json_object_ok``
    Asserts that it is given a representation of a JSON object (i.e. a ``HASH``
    ref).

  ``json_keys_ok``
    Asserts that it is given a representation of a JSON object and that
    additionally it defines values for all of the key names given.

  ``json_list_ok``
    Asserts that it is given a representation of a JSON object (i.e. an
    ``ARRAY`` ref).

  ``json_number_ok``
    Asserts that it is given a likely representation of a JSON number (i.e. a
    non-reference that passes the ``looks_like_number()`` test). Because of the
    limits of the JSON-to-Perl decoding process it isn't possible to definitely
    assert this originally came from a number in the JSON encoding, as compared
    to a string representation of a number.

  ``json_string_ok``
    Asserts that it is given a likely representation of a JSON string (i.e. a
    non-reference). Note that this will also be true of values that were
    originally JSON numbers or booleans.

  ``json_nonempty_string_ok``
    Asserts that it is given a likely representation of a JSON string, and
    additionally that the string is not empty.
