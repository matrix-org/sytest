# vim:ft=perl

requires 'Crypt::NaCl::Sodium';  # this is a right pain to install... :/
requires 'Data::Dump';
requires 'File::Basename';
requires 'File::Path';
requires 'Future';
requires 'Getopt::Long';
requires 'IO::Async::Loop';
requires 'IO::Async::SSL';
requires 'IO::Socket::SSL';
requires 'JSON';
requires 'List::Util', '>= 1.33';
requires 'List::UtilsBy';
requires 'MIME::Base64';
requires 'Module::Pluggable';
requires 'Net::Async::HTTP', '>= 0.36';
requires 'Net::Async::HTTP::Server', '>= 0.08';
requires 'Protocol::Matrix';  ## WORK IN PROGRESS
requires 'Struct::Dumb';
requires 'URI::Escape';
requires 'YAML';
