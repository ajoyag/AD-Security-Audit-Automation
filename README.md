# Automated Security Auditing System

## Overview
This project aims to automate the repetitive task of auditing multiple machines across different network blocks by remotely collecting system and user information from Active Directory (AD) environments. It leverages PowerShell scripts to retrieve data using administrator credentials, streamlining security audits and improving efficiency.

This work is part of my internship, and I’m building the system step-by-step, starting with setting up a virtual AD environment.

---

## Project Goal
Automate security auditing across **n** machines by remotely collecting necessary data from each device within an Active Directory domain using PowerShell scripts running with administrator privileges.

---

## Tech Stack
- **PowerShell** — primary scripting language  
- **Active Directory** — target environment for auditing  
- **Windows Server** — Domain Controller setup in virtual lab  
- **VMware** — virtualization platform to create a test AD environment  

---

## Project Roadmap

| Part | Description                                        | Status       |
|-------|--------------------------------------------------|--------------|
| 1     | [Create virtual Active Directory environment](https://github.com/ajoyag/Security-Audit-Automation/blob/main/Create_Virtual_AD_Environment/Creating%20a%20Virtual%20AD%20Environment.md)       | ✅ Completed |
| 2     | [Develop & test script for a single local machine](https://github.com/ajoyag/Security-Audit-Automation/blob/main/Create_Test_for_Local_Machine_Script/Create%20and%20Test%20a%20Single%20Local%20Machine%20Script.md)  | 🔃 In-Progress  |
| 3     | Extend script with administrator rights on local machine | 🔜 Upcoming  |
| 4     | Scale to multiple local machines with admin rights | 🔜 Upcoming  |
| 5     | Execute multi-machine audit remotely with admin rights | 🔜 Upcoming  |

---

## Repository Structure

Automated-Security-Auditing-System/  

├── README.md  
├── LICENSE (optional)  
├── scripts/  
│ ├── single_machine_audit.ps1  
│ ├── single_machine_admin_audit.ps1  
│ ├── multi_machine_admin_audit.ps1  
│ └── remote_multi_machine_audit.ps1  
├── setup/  
│ ├── vmware_lab_setup.md  
│ └── ad_configuration_steps.md  
├── logs/  
│ └── sample_audit_log.txt  
├── screenshots/  
│ └── vm_setup.png  
└── .gitignore

---

## How to Run the Scripts

1. Clone this repository.  
2. Set up your environment (see lab setup guide).  
3. Navigate to the `scripts` folder.  
4. Run the appropriate PowerShell script depending on your testing phase.

Example to run the single machine script:

Powershell
``.\single_machine_audit.ps1``

## Sample Output

Logs and sample output files will be provided in the `logs/` directory as the scripts evolve.

## Future Improvements

-   Enhance script robustness and error handling
   
-   Add reporting and alerting capabilities
   
-   Integrate with CI/CD pipelines for continuous auditing
   
-   Open source the project for community contributions

## Author


**AJOY A G**  
Internship Project | Cybersecurity Automation  
[LinkedIn Profile](https://www.linkedin.com/in/ajoyag/)
[GitHub](https://github.com/ajoyag)
