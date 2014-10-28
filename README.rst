Installing
----------

If you haven't set up cpan then run::

    cpan -v
    perl -Mlocal::lib >> ~/.profile
    . ~/.profile

Install sytest and its dependencies::

    git clone https://github.com/matrix-org/sytest
    cd sytest
    cpanm --installdeps .
    cd ..

Install synapse::

    pip install pynacl --user # Work around pynacl directory sort bug.
    git clone https://github.com/matrix-org/synapse
    cd synapse
    git checkout develop
    python setup.py develop --user
    python setup.py test
    cd ..

Running
-------

Run sytest::

    cd sytest
    ./run-tests.pl

