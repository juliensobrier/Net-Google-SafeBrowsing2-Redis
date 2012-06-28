package Net::Google::SafeBrowsing2::Redis;

use strict;
use warnings;

use base 'Net::Google::SafeBrowsing2::Storage';

use Carp;
use Redis::hiredis;


our $VERSION = '0.2';


=head1 NAME

Net::Google::SafeBrowsing2::Redis - Redis as back-end storage for the Google Safe Browsing v2 database

=head1 SYNOPSIS

  use Net::Google::SafeBrowsing2::Redis;

  my $storage = Net::Google::SafeBrowsing2::Redis->new(host => '127.0.0.1', database => 1);
  ...

=head1 DESCRIPTION

This is an implementation of L<Net::Google::SafeBrowsing2::Storage> using Redis.

=cut


=head1 CONSTRUCTOR

=over 4

=head2 new()

Create a Net::Google::SafeBrowsing2::Redis object

  my $storage = Net::Google::SafeBrowsing2::Redis->new(
      host     => '127.0.0.1', 
      database => 0, 
  );

Arguments

=over 4

=item host

Optional. Redis host name. "127.0.01" by default

=item database

Optional. Redis database name to connect to. 0 by default.

=item port

Optional. Redis port number to connect to. 6379 by default.


=back


=back

=cut

sub new {
	my ($class, %args) = @_;

	my $self = { # default arguments
		host		=> '127.0.0.1',
		database	=> 0,
		port		=> 6379,

		%args,
	};

	bless $self, $class or croak "Can't bless $class: $!";

    return $self;
}

=head1 PUBLIC FUNCTIONS

=over 4

See L<Net::Google::SafeBrowsing2::Storage> for the list of public functions.

=cut


sub redis {
	my ($self, %args) 	= @_;

	if (! exists ($self->{redis})) {
		my $redis = Redis::hiredis->new();
		$redis->connect( $self->{host}, $self->{port} );
		$redis->select( $self->{database} );
		$self->{redis} = $redis;
	}

	return $self->{redis};
}


sub add_chunks {
	my ($self, %args) 	= @_;
	my $type			= $args{type}		|| 'a';
	my $chunknum		= $args{chunknum}	|| 0;
	my $chunks			= $args{chunks}		|| [];
	my $list			= $args{'list'}		|| '';

	if ($type eq 's') {
		$self->add_chunks_s(chunknum => $chunknum, chunks => $chunks, list => $list);
	}
	elsif ($type eq 'a') {
		$self->add_chunks_a(chunknum => $chunknum, chunks => $chunks, list => $list);
	}

	my $key = $type . $list;
	$self->redis()->zadd($key, $chunknum, $chunknum);

	if (scalar @$chunks == 0) { # keep empty chunks
		my $key = $type . $chunknum . $list;
		$self->redis()->hmset($key, "list", $list, "hostkey", '', "prefix", '', "chunknum", $chunknum);
	}
}

sub add_chunks_a {
	my ($self, %args) 	= @_;
	my $chunknum		= $args{chunknum}	|| 0;
	my $chunks			= $args{chunks}		|| [];
	my $list			= $args{'list'}		|| '';

	# TODO: use 1 command to set all values
	foreach my $chunk (@$chunks) {
		my $key = "a$chunknum" . $chunk->{host} . $chunk->{prefix} . $list;
		$self->redis()->hmset($key, "list", $list, "hostkey", $chunk->{host}, "prefix", $chunk->{prefix}, "chunknum", $chunknum);
	}
}

sub add_chunks_s {
	my ($self, %args) 	= @_;
	my $chunknum		= $args{chunknum}	|| 0;
	my $chunks			= $args{chunks}		|| [];
	my $list			= $args{'list'}		|| '';

	# TODO: use 1 command to set all values
	foreach my $chunk (@$chunks) {
		my $key = "s$chunknum" . $chunk->{host} . $chunk->{prefix} . $chunk->{add_chunknum} . $list;
		$self->redis()->hmset($key, "list", $list, "hostkey", $chunk->{host}, "prefix", $chunk->{prefix}, "addchunknum ", $chunk->{add_chunknum}, "chunknum", $chunknum);
	}
}

# TODO: avoid duplicate code
sub get_add_chunks {
	my ($self, %args) 	= @_;
	my $hostkey			= $args{hostkey}	|| '';

	my @list = ();
	my $keys = $self->redis()->keys("a$hostkey*");

	# TODO: use 1 command to get all values
	foreach my $key (@$keys) {
		my $chunk = to_hash($self->redis()->hgetall($key));
		push(@list, $chunk) if ($chunk->{hostkey} eq $hostkey);
	}

	return @list;
}


sub get_sub_chunks {
	my ($self, %args) = @_;
	my $hostkey			= $args{hostkey}	|| '';

	my @list = ();
	my $keys = $self->redis()->keys("s$hostkey*");

	# TODO: use 1 command to get all values
	foreach my $key (@$keys) {
		my $chunk = to_hash($self->redis()->hgetall($key));
		push(@list, $chunk) if ($chunk->{hostkey} eq $hostkey);
	}

	return @list;
}


sub get_add_chunks_nums {
	my ($self, %args) 	= @_;
	my $list			= $args{'list'}		|| '';

	return $self->get_chunks_nums(type => 'a', list => $list);
}

sub get_sub_chunks_nums {
	my ($self, %args) 	= @_;
	my $list			= $args{'list'}		|| '';

	return $self->get_chunks_nums(type => 's', list => $list);
}

sub get_chunks_nums {
	my ($self, %args) 	= @_;
	my $list			= $args{'list'}		|| '';
	my $type			= $args{type}		|| 'a';

	my $key = "$type$list";
	my $values = $self->redis()->zrangebyscore($key, "-inf", "+inf");

	return @$values;
}


sub delete_add_ckunks {
	my ($self, %args) 	= @_;
	my $chunknums		= $args{chunknums}	|| [];
	my $list			= $args{'list'}		|| '';

# 	foreach my $num (@$chunknums) {
# 		my $keys = $self->redis()->keys("a$num*$list");
# 		foreach my $key (@$keys) {
# 			$self->redis()->del($key) if ($self->redis()->hget($key, "chunknum") == $num);
# 		}
# 
# 		$self->redis()->zrem("a$list", $num);
# 	}

	
	my $keys = $self->redis()->keys("a$list");
	foreach my $key (@$keys) {
		foreach my $num (@$chunknums) {
			$self->redis()->del($key) if ($key =~ /^a$num/ && $self->redis()->hget($key, "chunknum") == $num);
		}
	}

	foreach my $num (@$chunknums) {
		$self->redis()->zrem("a$list", $num);
	}
}


sub delete_sub_ckunks {
	my ($self, %args) 	= @_;
	my $chunknums		= $args{chunknums}	|| [];
	my $list			= $args{'list'}		|| '';

# 	foreach my $num (@$chunknums) {
# 		my $keys = $self->redis()->keys("s$num*$list");
# 		foreach my $key (@$keys) {
# 			$self->redis()->del($key) if ($self->redis()->hget($key, "chunknum") == $num);
# 		}
# 
# 		$self->redis()->zrem("s$list", $num);
# 	}

	my $keys = $self->redis()->keys("s*$list");
	foreach my $key (@$keys) {
		foreach my $num (@$chunknums) {
			$self->redis()->del($key) if ($key =~ /^s$num/ && $self->redis()->hget($key, "chunknum") == $num);
		}
	}

	foreach my $num (@$chunknums) {
		$self->redis()->zrem("s$list", $num);
	}
}

sub get_full_hashes {
	my ($self, %args) = @_;
	my $chunknum		= $args{chunknum}	|| 0;
	my $timestamp		= $args{timestamp}	|| 0;
	my $list			= $args{list}		|| '';

	my @hashes = ();

	my $keys = $self->redis()->keys("h$chunknum*$list");
	foreach my $key (@$keys) {
		my $chunk = to_hash($self->redis()->hgetall($key));
		push(@hashes, $chunk->{hash}) if ($chunk->{chunknum} == $chunknum 
			&& exists($chunk->{timestamp}) && exists($chunk->{hash})
			&& $chunk->{timestamp} >= $timestamp);
	}

	return @hashes;
}

sub updated {
	my ($self, %args) 	= @_;
	my $time			= $args{'time'}	|| time();
	my $wait			= $args{'wait'}	|| 1800;
	my $list			= $args{'list'}	|| '';

	$self->redis()->hmset($list, "time", $time, "errors", 0, "wait", $wait);
}

sub update_error {
	my ($self, %args) 	= @_;
	my $time			= $args{'time'}	|| time();
	my $list			= $args{'list'}	|| '';
	my $wait			= $args{'wait'}	|| 60;
	my $errors			= $args{errors}	|| 1;

	$self->redis()->hmset($list, "time", $time, "errors", $errors, "wait", $wait);
}

sub last_update {
	my ($self, %args) 	= @_;
	my $list			= $args{'list'}	|| '';

	my $keys = $self->redis()->keys($list);
	if (scalar @$keys > 0) {
		return to_hash($self->redis()->hgetall($keys->[0]));
	}
	else { 
		return {'time' => 0, 'wait' => 0, errors => 0};
	}
}

sub add_full_hashes {
	my ($self, %args) 	= @_;
	my $timestamp		= $args{timestamp}		|| time();
	my $full_hashes		= $args{full_hashes}	|| [];

	foreach my $hash (@$full_hashes) {
		my $key = "h" . $hash->{chunknum} . $hash->{hash} . $hash->{list};
		$self->redis()->hset($key, "chunknum",  $hash->{chunknum}, "hash",  $hash->{hash}, "timestamp", $timestamp);
	}
}

# sub delete_full_hashes_1 {
# 	my ($self, %args) 	= @_;
# 	my $chunknums		= $args{chunknums}	|| [];
# 	my $list			= $args{list}		|| croak "Missing list name\n";
# 
# 	foreach my $num (@$chunknums) {
# 		my @keys = $self->redis()->keys("h$num*$list");
# 		foreach my $key (@keys) {
# 			$self->redis()->del($key);
# 		}
# 	}
# }

sub delete_full_hashes {
	my ($self, %args) 	= @_;
	my $chunknums		= $args{chunknums}	|| [];
	my $list			= $args{list}		|| croak "Missing list name\n";

	my @keys = $self->redis()->keys("h*$list");
	foreach my $key (@keys) {
		foreach my $num (@$chunknums) {
			$self->redis()->del($key) if ($key =~ /^h$num/);
		}
	}
}



sub full_hash_error {
	my ($self, %args) 	= @_;
	my $timestamp		= $args{timestamp}	|| time();
	my $prefix			= $args{prefix}		|| '';

	my $key = "eh$prefix";

	my $keys = $self->redis()->keys($key);
	if (scalar(@$keys) == 0) {
			$self->redis()->hset($key, "prefix", $prefix, "errors", 0, "timestamp", $timestamp);
	}
	else {
		$self->redis()->hincrby($key, "errors", 1);
		$self->redis()->hset($key, "timestamp", $timestamp);
	}
}

sub full_hash_ok {
	my ($self, %args) 	= @_;
	my $timestamp		= $args{timestamp}	|| time();
	my $prefix			= $args{prefix}		|| '';

	$self->redis()->del("eh$prefix");
}

sub get_full_hash_error {
	my ($self, %args) 	= @_;
	my $prefix			= $args{prefix}		|| '';

	my $key = "eh$prefix";
	my $keys = $self->redis()->keys($key);

	if (scalar(@$keys) > 0 ) {
		return to_hash( $self->redis()->hgetall($key) );
	}
	else {
		# no error
		return undef;
	}
}

# TODO: init() to set empty mac keys
sub get_mac_keys {
	my ($self, %args) 	= @_;

	if (scalar($self->redis()->keys("mac")) == 0) {
		return { client_key => '', wrapped_key => '' };
	}
	else {
		return to_hash($self->redis()->hgetall("mac"));
	}
}

sub add_mac_keys {
	my ($self, %args) 	= @_;
	my $client_key		= $args{client_key}		|| '';
	my $wrapped_key		= $args{wrapped_key}	|| '';

	$self->redis()->hmset("mac", "client_key", $client_key, "wrapped_key", $wrapped_key);
}

sub delete_mac_keys {
	my ($self, %args) 	= @_;

	$self->redis()->hmset("mac", "client_key", '', "wrapped_key", '');
}


sub reset {
	my ($self, %args) 	= @_;

	$self->redis()->flushdb();
}


sub to_hash {
	my ($data) = @_;

	my $result = { };

	my @elements = @$data;
	while(my ($key, $value) = splice(@elements,0,2)) {
		$result->{$key} = $value
	}

	return $result;
}

=back

=head1 SEE ALSO

See L<Net::Google::SafeBrowsing2> for handling Google Safe Browsing v2.

See L<Net::Google::SafeBrowsing2::Storage> for the list of public functions.

See L<Net::Google::SafeBrowsing2::Sqlite> for a back-end using Sqlite.

Google Safe Browsing v2 API: L<http://code.google.com/apis/safebrowsing/developers_guide_v2.html>


=head1 AUTHOR

Julien Sobrier, E<lt>jsobrier@zscaler.comE<gt> or E<lt>julien@sobrier.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Julien Sobrier

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

1;