# How many more users do we want?
my $REMOTE_USERS = 2;

prepare "Remote users",
   requires => [qw( api_clients )],

   provides => [qw( remote_users )],

   do => sub {
      my ( $clients ) = @_;
      my $http = $clients->[1];

      Future->needs_all( map {
         my $uid = "19remote-users-$_";

         matrix_register_user( $http, $uid )
      } 1 .. $REMOTE_USERS
      )->then( sub {
         my @users = @_;

         provide remote_users => \@users;

         Future->done();
      });
   };
