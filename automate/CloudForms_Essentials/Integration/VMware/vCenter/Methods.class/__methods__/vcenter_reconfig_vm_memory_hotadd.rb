=begin
  vcenter_reconfig_vm_memory_hotadd.rb

  Author: Kevin Morey <kevin@redhat.com>

  Description: This method changes a VM's memoryHotAddEnabled switch to true or false in vCenter

-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kevin@redhat.com>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-------------------------------------------------------------------------------
=end
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def login(client, username, password)
  result = client.call(:login) do
    message( :_this => "SessionManager", :userName => username, :password => password )
  end
  client.globals.headers({ "Cookie" => result.http.headers["Set-Cookie"] })
end

def logout(client)
  begin
    client.call(:logout) do
      message(:_this => "SessionManager")
    end
  rescue => logouterr
    log(:error, "Error logging out #{logouterr.class} #{logouterr}")
  end
end

$evm.root.attributes.sort.each { |k, v| log(:info,"Root:<$evm.root> Attributes - #{k}: #{v}")}

# Get vm object from root
vm = $evm.root['vm']
raise "VM object not found" if vm.nil?

# This method only works with VMware VMs currently
raise "Invalid vendor:<#{vm.vendor}>" unless vm.vendor.downcase == 'vmware'

if $evm.root['dialog_memoryhotaddenabled'].blank? || $evm.root['dialog_memoryhotaddenabled'] =~ (/(false|f|no|n|0)$/i)
  memoryHotAddEnabled = false
else
  memoryHotAddEnabled = true
end

begin
  require 'savon'

  log(:info,"Detected VM: #{vm.name} vendor: #{vm.vendor} provider: #{vm.ext_management_system.name} ems_ref: #{vm.ems_ref}")

  # get servername and credentials from vm.ext_management_system
  servername = vm.ext_management_system.ipaddress
  username = vm.ext_management_system.authentication_userid
  password = vm.ext_management_system.authentication_password

  client = Savon.client(
    :wsdl => "https://#{servername}/sdk/vim.wsdl",
    :endpoint => "https://#{servername}/sdk/",
    :ssl_verify_mode => :none,
    :ssl_version => :TLSv1,
    :raise_errors => false,
    :log_level => :info,
    :log => false
  )
  #client.operations.sort.each { |operation| log(:info, "Savon Operation: #{operation}") }

  # login and set cookie
  login(client, username, password)

  reconfig_vm_task_result = client.call(:reconfig_vm_task) do
    message( '_this' => vm.ems_ref, :attributes! => { 'type' => 'VirtualMachine' },
             'spec' => { 'memoryHotAddEnabled' => memoryHotAddEnabled }, :attributes! => { 'type' => 'VirtualMachineConfigSpec' }  ).to_hash
  end

  #log(:warn, "reconfig_vm_task_result: #{reconfig_vm_task_result.inspect}")
  log(:info, "reconfig_vm_task_result success?: #{reconfig_vm_task_result.success?}")

  logout(client)

rescue => err
  log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
