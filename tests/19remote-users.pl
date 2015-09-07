# How many more users do we want?
my $REMOTE_USERS = 2;

prepare "Remote users",
   requires => [qw( register_new_user v1_clients
                    can_register )],

   provides => [qw( remote_users )],

   do => sub {
      my ( $register_new_user, $clients ) = @_;
      my $http = $clients->[1];

      Future->needs_all( map {
         my $uid = "19remote-users-$_";

         $register_new_user->( $http, $uid )
      } 1 .. $REMOTE_USERS
      )->then( sub {
         my @users = @_;

         provide remote_users => \@users;

         Future->done();
      });
   };

prepare "Remote v2 users",
   requires => [qw( register_new_user v1_clients v2_clients can_register )],

   provides => [qw( remote_v2_users )],

   do => sub {
      my ( $register_new_user, $clients, $clients_v2 ) = @_;
      my $http = $clients->[1];

      Future->needs_all( map {
         my $uid = "19remote-v2-users-$_";
         # Register the users using the v1 API.
         $register_new_user->( $http, $uid )
      } 1 .. $REMOTE_USERS
      )->then( sub {
         my @users = @_;
         # For each of the Users that were registered set the http
         # client to be the v2 client rather than the v1 client.
         # We should fix this when it becomes possible to register
         # clients for sytest using the v2 register APIs.
         $_->http = $clients_v2->[1] for @users;

         provide remote_v2_users => \@users;

         Future->done();
      });
   };
