# Automated Tomcat Deployment on SLES 16 with Ansible and Cockpit (Using Native Zypper Package)

## Purpose

 This guide adapts the previous steps for SUSE Linux Enterprise Server (SLES) 16, leveraging the native Tomcat 11 package available in the SLES repositories (as of September 18, 2025). This eliminates the need to download and unpack from upstream Apache archives, making the deployment faster, more secure, and aligned with SUSE's packaging standards. The tomcat package installs Tomcat 11 to /usr/share/tomcat, creates the tomcat user/group automatically, and provides a pre-configured systemd service (tomcat.service). We'll use Ansible to install via zypper, apply custom configurations (e.g., port, manager user), and integrate with Cockpit.

Key Changes from Upstream Download:

- Repository: No need for extra repos beyond base SLES (Tomcat 11 is in the default Application:Web module or OSS repo).

- Paths: Tomcat at /usr/share/tomcat (not /opt/tomcat); configs in /usr/share/tomcat/conf/.

- Service: Uses package-provided /usr/lib/systemd/system/tomcat.service; we reload and enable it.

- Java: Still OpenJDK 17 (SLES 16 default).

- Customizations: Ansible templates for server.xml (port) and tomcat-users.xml (manager user/password) post-install.

- Enable Web Module: If not already, activate via SUSEConnect for web apps.

The Cockpit plugin with upfront questionnaire (for port, username, password) remains integrated for one-click deployment under Tools.

**Step 1:** Install Cockpit from the SUSE Package Hub

Enable SUSE Package Hub for SLES 16:
````
sudo SUSEConnect -p PackageHub/16/x86_64
````

Refresh Repositories and Install Cockpit:
````
sudo zypper refresh
sudo zypper install cockpit
````
Enable and Start Cockpit Service:
````
sudo systemctl enable --now cockpit.socket
````
Open Firewall Port for Cockpit:

````
sudo firewall-cmd --add-service=cockpit --permanent
sudo firewall-cmd --reload
````
Access Cockpit at https://<your_server_ip>:9090.

**Step 2:** Install Ansible

Enable Systems Management Module for SLES 16:
````
sudo SUSEConnect -p sle-module-systems-management/16/x86_64
````
Refresh Repositories and Install Ansible:
````
sudo zypper refresh
sudo zypper install ansible
````
Verify: ansible --version (expect 2.14+).

**Step 3:** Create the Ansible Project

Create the directory structure:
````
mkdir -p ~/ansible/tomcat-playbook/templates
cd ~/ansible/tomcat-playbook
````
Create the hosts Inventory File:
````
echo -e "[tomcat_servers]\nlocalhost ansible_connection=local" > hosts
````
Create the <ins>tomcat.service.j2</ins> Template File: Not needed, as the package provides the service. Skip this.

Create the Final deploy_tomcat.yml Playbook: Updated for native install. Includes post-install templates for customs.

````
cat <<EOF > deploy_tomcat.yml
---
- hosts: tomcat_servers
  become: yes
  vars:
    java_home_path: /usr/lib64/jvm/java-17-openjdk-17
    tomcat_config_dir: /etc/tomcat11
  tasks:
    - name: Install Java
      zypper:
        name: java-17-openjdk-headless
        state: present
        update_cache: yes

    - name: Install Tomcat 11 and related packages
      zypper:
        name:
          - tomcat11
          - tomcat11-webapps
          - tomcat11-admin-webapps
          - tomcat11-lib
        state: present
        update_cache: yes

    - name: Ensure JAVA_HOME in Tomcat environment
      lineinfile:
        path: /etc/tomcat11/tomcat.conf
        regexp: '^JAVA_HOME='
        line: "JAVA_HOME={{ java_home_path }}"
        create: yes
        owner: tomcat
        group: tomcat
        mode: '0644'
      notify: restart tomcat

    - name: Ensure Tomcat config directory exists
      file:
        path: "{{ tomcat_config_dir }}"
        state: directory
        owner: tomcat
        group: tomcat
        mode: '0755'

    - name: Check if server.xml exists
      stat:
        path: "{{ tomcat_config_dir }}/server.xml"
      register: server_xml_stat

    - name: Ensure server.xml exists
      copy:
        content: |
          <?xml version="1.0" encoding="UTF-8"?>
          <Server port="8005" shutdown="SHUTDOWN">
            <Service name="Catalina">
              <Connector port="8080" protocol="HTTP/1.1" connectionTimeout="20000" redirectPort="8443" />
              <Connector protocol="AJP/1.3" port="8009" redirectPort="8443" secretRequired="false" />
              <Engine name="Catalina" defaultHost="localhost">
                <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
              </Engine>
            </Service>
          </Server>
        dest: "{{ tomcat_config_dir }}/server.xml"
        owner: tomcat
        group: tomcat
        mode: '0644'
        force: no
      when: not server_xml_stat.stat.exists

    - name: Check if tomcat-users.xml exists
      stat:
        path: "{{ tomcat_config_dir }}/tomcat-users.xml"
      register: tomcat_users_stat

    - name: Ensure tomcat-users.xml exists
      copy:
        content: |
          <?xml version="1.0" encoding="UTF-8"?>
          <tomcat-users xmlns="http://tomcat.apache.org/xml"
                        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                        xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
                        version="1.0">
          </tomcat-users>
        dest: "{{ tomcat_config_dir }}/tomcat-users.xml"
        owner: tomcat
        group: tomcat
        mode: '0644'
        force: no
      when: not tomcat_users_stat.stat.exists

    - name: Check if Tomcat installation directory exists
      stat:
        path: /usr/share/tomcat11
      register: tomcat_install_stat

    - name: Ensure Tomcat ownership for installation directory
      file:
        path: /usr/share/tomcat11
        state: directory
        owner: tomcat
        group: tomcat
        recurse: yes
      when: tomcat_install_stat.stat.exists

    - name: Configure HTTP port in server.xml
      lineinfile:
        path: "{{ tomcat_config_dir }}/server.xml"
        regexp: '<Connector port="8080" protocol="HTTP/1.1"'
        line: "<Connector port=\"{{ tomcat_http_port | default('8080') }}\" protocol=\"HTTP/1.1\" connectionTimeout=\"20000\" redirectPort=\"8443\" />"
        backup: yes
      notify: restart tomcat

    - name: Configure shutdown port in server.xml
      lineinfile:
        path: "{{ tomcat_config_dir }}/server.xml"
        regexp: '<Server port="8005"'
        line: "<Server port=\"{{ tomcat_shutdown_port | default('8005') }}\" shutdown=\"SHUTDOWN\">"
        backup: yes
      notify: restart tomcat

    - name: Configure AJP port in server.xml
      lineinfile:
        path: "{{ tomcat_config_dir }}/server.xml"
        regexp: '<Connector protocol="AJP/1.3" port="8009"'
        line: "<Connector protocol=\"AJP/1.3\" port=\"{{ tomcat_ajp_port | default('8009') }}\" redirectPort=\"8443\" secretRequired=\"false\" />"
        backup: yes
      notify: restart tomcat

    - name: Add user and role to tomcat-users.xml
      blockinfile:
        path: "{{ tomcat_config_dir }}/tomcat-users.xml"
        marker: "<!-- {mark} ANSIBLE MANAGED BLOCK -->"
        block: |
          <role rolename="{{ tomcat_user_role | default('manager-gui') }}"/>
          <user username="{{ tomcat_username | default('admin') }}" password="{{ tomcat_password | default('changeme') }}" roles="{{ tomcat_user_role | default('manager-gui') }}"/>
        backup: yes
      notify: reload tomcat

    - name: Reload systemd
      systemd:
        daemon_reload: yes

    - name: Start and enable Tomcat
      systemd:
        name: tomcat
        state: started
        enabled: yes

    - name: Open firewall for HTTP port
      firewalld:
        port: "{{ tomcat_http_port | default('8080') }}/tcp"
        permanent: yes
        state: enabled
        immediate: yes

  handlers:
    - name: restart tomcat
      systemd:
        name: tomcat
        state: restarted

    - name: reload tomcat
      systemd:
        name: tomcat
        state: reloaded
EOF
````

**Step 4:** Execute the Playbook

From ~/ansible/tomcat-playbook:

````
ansible-playbook -i hosts deploy_tomcat.yml
````
For customs:
````
ansible-playbook -i hosts deploy_tomcat.yml -e tomcat_port=8081 -e tomcat_username=admin -e tomcat_password=securepass
````

**Step 5:** Verify the Deployment

Check Status:
````
sudo systemctl status tomcat.service
````
(Expect Active: active (running).)

Open Firewall:
````
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
````
Access: <ins>http://<your_server_ip>:8080</ins> (Tomcat welcome page). For manager: <ins>http://<ip>:8080/manager/html</ins> (login with customs).

## Integrating "deploy-tomcat" into Cockpit for SLES 16 under Tools

Same as before: Wrapper script and plugin for one-click with questionnaire.

**Step 1:** Move the Playbook to a Permanent Location

````
sudo mkdir -p /opt/ansible
sudo mv ~/ansible/tomcat-playbook /opt/ansible/
````

**Step 2:** Create the Wrapper Script

Updated for native paths and vars.

````
sudo cat <<EOF > /usr/local/bin/deploy-tomcat
#!/bin/bash

# Parse arguments
PORT=8080
USERNAME="admin"
PASSWORD="changeme"

while [[ \$# -gt 0 ]]; do
    case \$1 in
        --port) PORT="\$2"; shift 2 ;;
        --username) USERNAME="\$2"; shift 2 ;;
        --password) PASSWORD="\$2"; shift 2 ;;
        *) echo "Unknown option: \$1"; exit 1 ;;
    esac
done

echo "==============================================="
echo "Starting Tomcat 11 Deployment (Native SLES Package)..."
echo "Port: \$PORT | User: \$USERNAME"
echo "==============================================="
echo ""

cd /opt/ansible/tomcat-playbook

# Pass to Ansible
ansible-playbook -i hosts deploy_tomcat.yml -e tomcat_port="\$PORT" -e tomcat_username="\$USERNAME" -e tomcat_password="\$PASSWORD"

echo ""
echo "==============================================="
echo "Deployment Finished. Verify: sudo systemctl status tomcat.service"
echo "==============================================="
EOF
````
````
sudo chmod +x /usr/local/bin/deploy-tomcat
````

**Step 3:** Install the Cockpit Plugin

Same files as before (manifest.json, deploy.html, deploy.js from prior steps)—they work unchanged, as the script handles vars.

Copy if needed:
````
sudo mkdir -p /usr/share/cockpit/deploy-tomcat
````

<ins>Assuming you have the files from before; copy them here</ins>

````
sudo cp manifest.json deploy.html deploy.js /usr/share/cockpit/deploy-tomcat/  # Adjust path
sudo chown -R root:root /usr/share/cockpit/deploy-tomcat/
sudo chmod -R 755 /usr/share/cockpit/deploy-tomcat/
sudo systemctl restart cockpit
````

**Step 4:** Run from Cockpit under Tools

1.Log in to Cockpit.

2.Tools > Deploy Tomcat.

3.Check "Use custom settings", fill form (port, username, password).

4.Click Deploy Tomcat—runs native install with customs.

5.Output shows progress; verify in browser.

Check the status by running:

````
systemctl status tomcat.service
````

To stop Tomcat run:

````
systemctl stop tomcat.service
systemcstl disable tomcat.service
````


**Summary:**

- Advantages of Native Package: Simpler, auto-updates via zypper update tomcat, SUSE-maintained security patches.

- Customization: Questionnaire passes to Ansible for flexible configs.

- Troubleshooting: If Tomcat not in repo, run sudo SUSEConnect -p sle-module-legacy-applications/16/x86_64 or check zypper search tomcat. For Java issues, confirm path with readlink -f $(which java).

- Security: Change default password immediately; enable HTTPS for production.

This provides a streamlined, repo-based deployment fully integrated with Cockpit.


### Cleanup

Run these commands to remove any old playbook files or plugin attempts.
Bash

**Remove old Ansible project**
````
sudo rm -rf /opt/ansible/tomcat-playbook
````
**Remove old wrapper script**
````
sudo rm -f /usr/local/bin/deploy-tomcat
````
**Remove old Cockpit plugins**

````
sudo rm -rf /usr/share/cockpit/tomcat-deployer
sudo rm -rf /usr/share/cockpit/hello
sudo rm -rf /usr/share/cockpit/test
````

Below are screenshots examples from SLES 16.

<img width="646" height="579" alt="image" src="https://github.com/user-attachments/assets/66c75c43-f640-4677-8199-33ff804d818b" />

<img width="1023" height="579" alt="image" src="https://github.com/user-attachments/assets/7d254110-05d1-4da3-87d4-477ac66f9e32" />


<img width="1237" height="887" alt="image" src="https://github.com/user-attachments/assets/790bdea0-adfa-41e5-9770-74668d001929" />


========

