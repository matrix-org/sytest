# vim:ft=perl

# Sodium won't install without this.
requires 'Alien::Base::ModuleBuild';

requires 'Class::Method::Modifiers';
requires 'Data::Dump';
requires 'DBD::Pg';
requires 'Digest::HMAC_SHA1';
requires 'Digest::SHA';
requires 'File::Basename';
requires 'File::Path';
requires 'File::Slurper';
requires 'Future', '>= 0.33';
requires 'Getopt::Long';
requires 'IO::Async', '>= 0.69';
requires 'IO::Async::SSL';
requires 'IO::Socket::IP', '>= 0.04';
requires 'IO::Socket::SSL';
requires 'JSON';
requires 'List::Util', '>= 1.45';
requires 'List::UtilsBy', '>= 0.10';
requires 'MIME::Base64';
requires 'Module::Pluggable';
requires 'Net::Async::HTTP', '>= 0.39';
requires 'Net::Async::HTTP::Server', '>= 0.09';
requires 'Net::SSLeay', '>= 1.59';
requires 'Protocol::Matrix', '>= 0.02';
requires 'Struct::Dumb', '>= 0.04';
requires 'URI::Escape';
requires 'YAML';

# this is a right pain to install; use libcrypt-nacl-sodium-perl from matrix.org package repo if at all possible
requires 'Crypt::NaCl::Sodium';
