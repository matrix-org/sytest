# vim:ft=perl

requires 'Class::Method::Modifiers';

requires 'Crypt::Ed25519';

requires 'Data::Dump';

# DBD::Pg fails to install if DBI is not already installed before we start.
# (DBI goes into an architecture-dependent directory, which may not exist when
# the installation process starts; by doing the install in two steps, we force
# perl to rescan the library directories and add any new ones which it finds.)
requires 'DBI';

requires 'DBD::Pg';
requires 'Digest::HMAC_SHA1';
requires 'Digest::SHA';
requires 'Email::Address::XS';
requires 'Email::MIME';
requires 'File::Basename';
requires 'File::Path';
requires 'File::Slurper';

# Future 0.45 allows you to return immediate values from sequence functions.
requires 'Future', '>= 0.45';
requires 'Getopt::Long';
requires 'HTTP::Request';
requires 'IO::Async', '>= 0.69';
requires 'IO::Async::SSL';
requires 'IO::Socket::IP', '>= 0.04';
requires 'IO::Socket::SSL';
requires 'JSON';

# We don't have a hard dep on JSON::PP (JSON::XS would be fine), but
# JSON::PP 2.274 incorrectly encodes JSON::Number(0) as "0", so we don't
# want to end up using that by accident
requires 'JSON::PP', '>= 2.91';

requires 'List::Util', '>= 1.45';
requires 'List::UtilsBy', '>= 0.10';
requires 'MIME::Base64';
requires 'Module::Pluggable';
requires 'Net::Async::HTTP', '>= 0.39';
requires 'Net::Async::HTTP::Server', '>= 0.09';
requires 'Net::SSLeay', '>= 1.59';
requires 'Struct::Dumb', '>= 0.04';
requires 'URI::Escape';
requires 'YAML::XS';
