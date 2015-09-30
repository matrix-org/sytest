# A handy little structure for other scripts to find in 'user' and 'more_users'
our @EXPORT = qw( User );
struct User => [qw( http user_id access_token refresh_token eventstream_token saved_events pending_get_events )];
