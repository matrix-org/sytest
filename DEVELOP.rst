Developing
==========

SyTest consists of two basic parts; the core test runner program and its
associated helper modules, and a set of test scripts themselves. The overall
runner program controls startup and shutdown of a number of Synapse processes
by means of a helper module, and reads and executes tests specified in each of
the actual test scripts.

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
``multi_test`` which sequentially control the execution of all the tests.

Each call to ``test`` or ``multi_test`` takes a single positional argument
giving descriptive text to use as a caption, and a set of named arguments to
control how the test runs.

::

    test "Here is the caption of the test",
       ...

The following named arguments apply to a test. Each of them is optional, and
is described in more detail in the following sections.

``do``
    Provides a ``CODE`` reference (most likely in the form of an inline
    ``sub { ... }`` block) which contains the main activity of the test.

``check``
    Provides a ``CODE`` reference similar to the ``do`` argument, which
    contains "immediate" checking code for the test.

``requires``
    Provides an ``ARRAY`` reference giving a list of named requirements and
    fixture objects.

``critical``
    If true and the test fails, the entire test run will bail out at this
    point; no further tests will be attempted at all.

A call to ``test`` is a simplified version of ``multi_test`` which produces
only a single line of test output indicating success or failure automatically.
A call to ``multi_test`` can make use of additional functions within the body
in order to report success or failure of multiple steps within it. Aside from
this difference, the two behave identically.

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

The entire combination of one or both ``check`` blocks and the ``do`` block are
given a total deadline of 10 seconds between them. If they have not succeeded
by this time, they will be aborted and the test will fail.

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

Note that while it was the original intention for the test environment to
accumulate shared state that later tests can use, it leads to more fragile
tests simply because of that shared state. Where possible, fixtures should be
used instead, especially when the state would only nominally be shared in order
to reduce the amount of setup boilerplate code required to implement a test.
See the Fixtures section below.

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

Fixtures
--------

As an alternative to accumulating state as named values within the test
environment, fixtures are another feature provided to reduce the amount of test
setup and teardown code in individual test cases. A fixture is an object that
encapsulates the dual processes of creating some values or state for a test to
use, and of destroying or resetting that state afterwards. The fixture object
also stores the value it created once that has been set up, allowing the value
to be reused by multiple tests if they all share the same fixture object.

A fixture object is created by the ``fixture`` function, which takes the
following named arguments:

``setup``
    A required ``CODE`` reference to a block of code used to lazily create the
    actual value for the fixture; that is, the value that will be passed to the
    running test code that uses the fixture. This block yields its return value
    via a future.

``teardown``
    An optional ``CODE`` reference to a code block that will be invoked at the
    end of the test using the fixture. This can be used to perform any final
    tidying up that is required after the fixture value has been used. This
    block returns a future but the actual final value yielded from that is
    ignored.

``requires``
    An ``ARRAY`` reference giving named requirements and other fixture objects.

Once a fixture object is constructed, it has not yet actually invoked the
``setup`` code; that is deferred until the first time the fixture object is
actually needed by a test. By using fixtures to provide initial context or
values to a test is therefore lazy, and avoids performing any work if the test
is skipped.

Each fixture can declare named requirements or other fixture objects in its own
dependencies. In this way a recursive tree of abilities can be constructed.
The values of the named requirements and dependent fixtures are passed in to
the ``setup`` block.

If the fixture does not have a ``teardown`` block then it may be shared by
multiple tests; each subsequent test that uses the same fixture object will
receive the same value. The ``setup`` code will not be re-run; simply the value
that it returned the first time will be reused by the second.

If the fixture provides a ``teardown`` block, then it is invoked at the end of
the test, once the eventual pass or failure has been determined. This is passed
the fixture value, and is expected to return a future to provide a way to know
when it has finished executing; the final return value yielded by this future
is not important. After the ``teardown`` block is invoked, the fixture object
can no longer be reused by other tests; it should therefore be constructed
uniquely for just one test.

Because of the optional nature of the ``teardown`` block, there are then two
main kinds of fixtures:

- Fixtures that provide access to some (possibly-shared) resource that is
  lazily provisioned the first time a test requires it. These are fixtures
  that lack a ``teardown`` block.

- Fixtures that provide access to some resource that is created and destroyed
  over the lifetime of the test. These are fixtures that have a ``teardown``
  block.

The intented use for fixtures is that test files will provide wrapper functions
that create a new fixture object to encapsulate some common setup pattern that
later tests may require. Later tests can then simply invoke that function as
part of their ``requires`` list to have the setup for that fixture value
effectively folded into to the start of the test, so that the main body of the
``check`` or ``do`` block of that test is invoked with the value or context
already provisioned.
