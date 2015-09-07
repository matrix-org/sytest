# vim:ft=perl

requires 'Data::Dump';
requires 'File::Basename';
requires 'File::Path';
requires 'File::Slurp::Tiny';
requires 'Future';
requires 'Getopt::Long';
requires 'IO::Async::Loop';
requires 'IO::Async::SSL';
requires 'IO::Socket::IP', '>= 0.04';
requires 'IO::Socket::SSL';
requires 'Imager';
requires 'JSON';
requires 'List::Util', '>= 1.33';
requires 'List::UtilsBy';
requires 'MIME::Base64';
requires 'Module::Pluggable';
requires 'Net::Async::HTTP', '>= 0.39';
requires 'Net::Async::HTTP::Server', '>= 0.08';
requires 'Protocol::Matrix';
requires 'Struct::Dumb';
requires 'URI::Escape';
requires 'YAML';

# this is a right pain to install; use libcrypt-nacl-sodium-perl from matrix.org package repo if at all possible
requires 'Crypt::NaCl::Sodium';
