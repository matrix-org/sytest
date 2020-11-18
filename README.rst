SyTest
======

SyTest is an integration testing system for Matrix homeserver implementations;
primarily at present the Synapse server. It performs "black-box" testing, by
starting up multiple home server instances and testing the interaction using
regular HTTP interaction much as any other Matrix client would do. It can
output test results either to an interactive terminal, or as a TAP-style test
report, for continuous-integration test harnsses such as Jenkins.

Installing
----------

SyTest requires a number of dependencies that are easiest installed from CPAN.

1. If these are not being installed directly into the system perl (as root),
   then you will first have to arrange that ``cpan`` can install to somewhere
   writable as the non-root user you are running SyTest as, and that ``perl``
   can see that.

   Personally I arrange this by adding three lines to ``.profile``::

    export PERL5LIB=$HOME/lib/perl5
    export PERL_MB_OPT=--install_base=$HOME
    export PERL_MM_OPT=INSTALL_BASE=$HOME

   Alternatively, see https://metacpan.org/pod/local::lib#The-bootstrapping-technique

   If you have edited your ``.profile``, don't forget to ``source`` it again
   into your running shell.

#. If you have not run ``cpan`` before, it will prompt for answers to several
   questions when it performs the initial setup. Running it once with no
   arguments will give you a chance to answer these questions. Most likely you
   can just let it configure "automatically"::

    $ cpan

    CPAN.pm requires configuration, but most of it can be done automatically.
    If you answer 'no' below, you will enter an interactive dialog for each
    configuration option instead.

    Would you like to configure as much as possible automatically? [yes] 

    ...

    cpan[1]> exit
    Lockfile removed.

#. Fetch the ``sytest`` source and install its dependencies::

    git clone https://github.com/matrix-org/sytest
    cd sytest
    ./install-deps.pl
    cd ..

#. As ``sytest`` is intended for testing the synapse home server
   implementation, it is likely you'll want to fetch the source of that as
   well. By default SyTest will expect to find it in a sibling directory called
   ``synapse``::

    pip install pynacl --user # Work around pynacl directory sort bug.
    git clone https://github.com/matrix-org/synapse
    cd synapse
    git checkout develop
    python setup.py develop --user
    python setup.py test
    cd ..

   Synapse does not need to be installed, as SyTest will run it directly from
   its source code directory.

Additionally, a number of native dependencies are required. To install these
dependencies on an Ubuntu/Debian-derived Linux distribution, run the following::

    sudo apt install libpq-dev build-essential

Installing on OS X
------------------
Dependencies can be installed on OS X in the same manner, except that packages
using NaCl / libsodium may fail. This can be worked around by:

Installing libsodium manually, eg.::

    $ brew install libsodium

and confirm it is installed correctly and visible to pkg-config. It should give
some configuration output, rather than an error::

    $ pkg-config --libs libsodium
    -L/usr/local/Cellar/libsodium/1.0.8/lib -lsodium

Then force an install of Crypt::NaCl::Sodium::

    $ cpan
    cpan> force install Crypt::NaCl::Sodium

You may also need to force install Shell::Guess, and manually install
DBI before DBD::Pg, otherwise DBD::Pg will fail with::

    No rule to make target '.../auto/DBI/Driver_xst.h'

Then run install-deps.pl as normal.

Running
-------

To run SyTest with its default settings, simply invoke the ``run-tests.pl``
script with no additional arguments::

    cd sytest
    ./run-tests.pl

If the Synapse source is checked out in a different location, this can be set
with ``--synapse-directory``::

    ./run-tests.pl --synapse-directory /home/synapse/synapse

If it is necessary to run the synapse server with a particular python
interpreter (for example, to run it within a virtualenv), this can be done
using ``--python``::

    ./run-tests.pl --python ../synapse/env/bin/python

To obtain greater visibility on why a particular test is failing, two
additional options can be passed to print extra information. The
``--client-log`` flag (shortened to ``-C``) will print HTTP requests made and
responses received::

    ./run-tests.pl -C

The ``--server-log`` flag (shortened to ``-S``) will print lines from the
Synapse server's standard error stream::

    ./run-tests.pl -S

To run only a subset of tests in certain files, name the files as additional
arguments::

    ./run-tests.pl tests/20profile-events.pl

To run synapse with a specific logging configuration, create a YAML file
suitable for dictConfig_ called ``log.config`` (it can be copied from a running
synapse) and place it within the homeserver configuration directory
(``localhost-<port>``).

.. _dictConfig: https://docs.python.org/2/library/logging.config.html#logging.config.dictConfig

Sytest supports plugins. Plugins follow the same project structure as sytest and can be placed
in the `plugins` directory.
To override the path of the plugins directory set the env var `SYTEST_PLUGINS` to another directory.

Currently only Homeserver and Output Implementations are supported in plugins.

Developing
----------

For more information on developing SyTest itself (maintaining or writing new
tests) see the `DEVELOP.rst` file.


Postgres Template Database
--------------------------

When testing with postgres SyTest will check if there is a database named
`sytest_template` and will create the test databases using that as a template.
This can be used to greatly reduce the time to create databases as they don't
need to be created from scratch.

The easiest way to create the template database is to start a HS pointing at
the database and stop it once the database has been created.
