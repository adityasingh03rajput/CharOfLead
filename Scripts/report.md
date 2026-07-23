1
FORM 2
THE PATENTS ACT, 1970
(39 of 1970)
5 &
The Patents Rules, 2003
COMPLETE SPECIFICATION (see section 10)
A SYSTEM AND METHOD FOR OFFLINE WI-FI-BASED ATTENDANCE USING MDNS
10 AND FINGERPRINT AUTHENTICATION
15
20
25
The following specification particularly describes the invention and the manner in which it is to be
performed.
2
FIELD OF THE INVENTION:
30
The present invention relates to the field of computer networks, mobile computing, and secure
authentication systems. More particularly, it pertains to a system and method for managing attendance
over a local Wi-Fi network using multicast DNS (mDNS) for device discovery and mobile fingerprint
authentication for user verification.
35
BACKGROUND:
 The present invention relates to attendance management systems that employ wireless
communication and biometric verification to record and authenticate the presence of users within a
40 defined area such as a classroom, workplace, or event space. The field encompasses computer
networks, mobile computing, and secure authentication systems that use Wi-Fi, multicast DNS
(mDNS) or DNS-based Service Discovery (DNS-SD), TCP/IP communication and on-device
biometric sensors such as fingerprint readers. Conventional attendance systems available in the art
are predominantly network-dependent or require dedicated biometric terminals, which limit their
45 applicability in locations with unreliable connectivity or budget constraints.
Several prior-art documents illustrate various approaches to automated attendance but suffer from
technical limitations that the present invention overcomes. For example Chinese Patent
CN103886648A titled as “Attendance system based on WIFI (Wireless Fidelity) signals of cell
phone” by Zhuang Nanqing, discloses an attendance system based on detecting mobile phones’ Wi50 Fi signals and automatically recording presence without app installation. While convenient, this
system depends on passive radio-signal detection and does not perform any biometric or
cryptographic verification, making it vulnerable to proxy or spoofed attendance.
Similarly an United States Patent US7826645B1 titled “Wireless fingerprint attendance system “ by
Joseph D. Cayen, teaches a wireless fingerprint attendance system using a dedicated fingerprint
55 scanner that transmits scanned data to a server. Although it allows offline matching, it requires
specialized hardware and central synchronization, lacking a purely smartphone-based
implementation and zero-configuration connectivity.
3
From these references, it is evident that existing systems either depend on constant internet
connectivity or external servers for verification, use passive signal detection prone to spoofing, or
60 require dedicated biometric terminals. None of them discloses or suggests a combined architecture in
which a teacher’s mobile device locally advertises an attendance session over Wi-Fi using mDNS,
students’ mobile devices automatically discover that session without manual configuration, and each
attendance submission is authenticated by mobile fingerprint verification that is cryptographically
bound to a session-specific token or nonce to prevent replay and proxy attacks.
65 Therefore, there exists a need for an improved attendance system that operates entirely offline within
a local Wi-Fi network, provides zero-configuration discovery, ensures that only physically present
users can mark attendance, and records verifiable entries in real time.The present invention addresses
these needs by providing a system and method for offline Wi-Fi-based attendance using mDNS and
fingerprint authentication.
70 OBJECTIVES OF THE INVENTION:
The primary objective of the present invention is to provide an offline Wi-Fi-based attendance system
and method that ensures secure, real-time, and tamper-proof attendance recording using mDNS-based
session discovery and mobile fingerprint authentication, thereby eliminating the dependency on
continuous internet connectivity and preventing proxy or fraudulent attendance. The system seeks to
75 overcome the limitations of existing network-dependent or hardware-based attendance systems,
which often require central servers, manual configuration, or costly biometric terminals.
Another objective of the invention is to implement a zero-configuration device discovery mechanism
through multicast DNS (mDNS), enabling student devices to automatically identify and connect to
80 the teacher’s attendance session within a local Wi-Fi network without manual IP entry or external
setup. This simplifies the user experience and ensures scalability in classroom or enterprise
environments.
A further objective of the invention is to enhance attendance security by incorporating mobile
85 fingerprint authentication at the student device level, such that attendance can only be marked by
verified users. By binding the biometric fingerprint data with a session-specific cryptographic token,
the invention prevents unauthorized or proxy attendance and strengthens data integrity.
4
The invention also has the objective of introducing a cryptographic authentication protocol that
90 generates a session token and nonce value at the teacher’s device, which must be signed and validated
by the student device within a short time frame. This ensures that every attendance event is uniquely
bound to a valid local session and cannot be replayed or spoofed from outside the classroom.
Another objective is to enforce local presence verification through airplane mode activation and Wi95 Fi-only communication, ensuring that attendance requests originate solely from devices connected to
the same classroom Wi-Fi network. This mechanism prevents remote submissions and provides proof
of physical presence without relying on GPS or external connectivity.
A further objective of the invention is to enable real-time attendance compilation and offline data
100 storage at the teacher’s device, where verified entries are timestamped, encrypted, and stored locally
in a secure database. Once internet connectivity becomes available, the system can synchronize
attendance data safely to a cloud or institutional server without data loss or tampering.
Additionally, the invention aims to reduce communication overhead and latency by utilizing
105 lightweight TCP communication within the local Wi-Fi network, ensuring that session discovery,
fingerprint verification, and attendance logging are completed within five seconds, even for multiple
simultaneous users.
Another objective is to improve proxy-prevention efficiency by combining Wi-Fi BSSID verification,
110 RSSI-based range enforcement, and fingerprint-bound authentication, providing a measurable
improvement of 30%–35% over conventional Wi-Fi or biometric attendance systems in terms of
reliability and fraud resistance.
The invention further has the objective of providing a secure, scalable, and cost-effective digital
115 attendance framework that operates entirely on standard Android smartphones, allowing deployment
in educational institutions, offices, and training environments without the need for dedicated servers
or hardware infrastructure.
5
Finally, the invention aims to establish a tamper-resistant, privacy-preserving attendance verification
120 mechanism that safeguards biometric and session data through local encryption, eliminates cloud
dependency during operation, and delivers a practical, real-world solution for secure and efficient
attendance management in offline environments.
SUMMARY:
125
The present invention provides a system and method for offline Wi-Fi-based attendance that securely
verifies user identity and physical presence without requiring continuous internet connectivity or
dedicated biometric terminals. The invention integrates multicast DNS (mDNS)-based automatic
service discovery, TCP-based local data exchange, and mobile fingerprint authentication into a
130 unified architecture that enables real-time, tamper-proof attendance recording in classroom or
enterprise environments.
In one embodiment, the teacher device functions as a local server that initiates an attendance session,
generates a unique session token and classroom code, and broadcasts the session details over the local
135 Wi-Fi network using the mDNS/DNS-SD protocol. A plurality of student devices running the
corresponding client application automatically discover this session through mDNS advertisements
within the same Wi-Fi subnet, eliminating the need for manual IP entry or centralized configuration.
Each student device performs biometric fingerprint authentication using the mobile sensor and
generates a fingerprint hash that is cryptographically bound to the current session token and nonce
140 value. A secure authentication token, computed for example as
AuthToken = HMAC(SessionToken ∥ FingerprintHash, AppSecretKey),
is transmitted via a local TCP connection to the teacher device. The teacher device validates the token,
ensures that the request originates from within the classroom Wi-Fi network, and records the
145 attendance entry only after successful verification.
To enforce physical presence and prevent proxy attendance, the system optionally requires the student
devices to operate in airplane mode with Wi-Fi enabled, thereby confining all communication to the
local network. The teacher device maintains a local encrypted database that stores verified attendance
6
150 records with timestamps and device identifiers. Once internet connectivity becomes available, the
data can be securely synchronized with an online or institutional database.
The invention thus overcomes the limitations of existing internet-dependent or hardware-bound
attendance systems by providing a zero-configuration, offline, and privacy-preserving solution.
155 Through the combination of mDNS-based discovery, fingerprint-bound cryptographic verification,
and secure local storage, the system achieves rapid (≈ 5 seconds) and accurate attendance validation
while ensuring that only physically present and authenticated users are recorded. The architecture is
fully software-based, scalable to multiple devices on standard Wi-Fi networks, and deployable on
commercial smartphones without additional infrastructure.
160
BRIEF DESCRIPTION OF THE DRAWINGS:
The foregoing summary, as well as the following detailed description of the invention, will be better
understood when read in conjunction with the appended drawings. For the purpose of assisting in the
165 explanation of the invention, there are shown in the drawings, embodiments that are presently
preferred and considered illustrative. It should be understood, however, that the invention is not
limited to the precise arrangements and instrumentalities shown therein the drawings:
FIG. 1 illustrates Flowchart of the Offline Wi-Fi-Based Attendance Process Using mDNS
and Fingerprint Authentication.
170 FIG. 2 Shows the Sequence Diagram Illustrating the Smart Offline Wi-Fi-Based Attendance
Process Using mDNS and Fingerprint Authentication,
FIG. 3 Depicts the Graphical User Interface of the Teacher Application for Attendance
Session Management,
FIG. 4 Depicts the Graphical User Interface of the Student Application for Attendance
175 Session Management,
7
180 REFERENCE NUMERALS:
100- System for Offline Wi-Fi-Based Attendance Process Using mDNS and Fingerprint
Authentication
DETAILED DESCRIPTION OF THE INVENTION:
185
The present invention will now be described more fully hereinafter. For the purposes of the following
detailed description, it is to be understood that the invention may assume various alternative
variations and step sequences, except where expressly specified to the contrary. Thus, before
describing the present invention in detail, it is to be understood that this invention is not limited to
190 particularly exemplified systems or embodiments that may, of course, vary. The use of examples
anywhere in this specification including examples of any terms discussed herein is illustrative only,
and in no way limits the scope and meaning of the invention or of any exemplified term. Likewise,
the invention is not limited to various embodiments given in this specification.
As used herein, the singular forms "a," "an," and "the" include plural reference unless the context
195 clearly dictates otherwise. The term "and/or" means one or all of the listed elements or a combination
of any two or more of the listed elements.
The terms “preferred” and “preferably” refer to embodiments of the invention that may afford certain
benefits, under certain circumstances. However, other embodiments may also be preferred, under the
same or other circumstances. Furthermore, the recitation of one or more preferred embodiments does
200 not imply that other embodiments are not useful, and is not intended to exclude other embodiments
from the scope of the invention.
When the term “about” is used in describing a value or an endpoint of a range, the disclosure should
be understood to include both the specific value and endpoint referred to.
As used herein the terms “comprises”, “comprising”, “includes”, “including”, “containing”,
205 “characterized by”, “having” or any other variation thereof, are intended to cover a non-exclusive
inclusion
8
The present invention provides an offline, network-local attendance system and method that enables
secure and verifiable attendance recording through Wi-Fi connectivity, multicast DNS (mDNS)
210 service discovery, TCP communication, and mobile fingerprint authentication. The system functions
without dependence on continuous internet or external servers and is specifically designed for
educational or organizational environments where secure attendance verification and ease of
deployment are critical.
215 The architecture includes two principal entities:
• Teacher Device (Server Side): Configured to initiate an attendance session, generate a unique
classroom code, and broadcast the session using mDNS. It hosts a local TCP server to receive
and verify attendance submissions.
• Student Devices (Client Side): Configured to automatically discover the broadcasted session
220 using mDNS, connect via TCP, authenticate users through on-device fingerprint scanning,
and submit encrypted verification tokens for validation.
During operation, the teacher’s application advertises the session locally using mDNS/DNS-SD
protocols conforming to RFC 6762 and RFC 6763. Student devices connected to the same Wi-Fi
225 subnet automatically detect the teacher’s session without manual IP configuration. Each student then
enters the classroom code and performs fingerprint authentication. The student device generates a
cryptographically signed token that binds the session identifier and fingerprint hash using an HMAC
function. The token is transmitted to the teacher’s device through a secure TCP channel, where it is
verified and logged in real time.
230
By enforcing airplane-mode operation with Wi-Fi enabled, the system guarantees that all
authenticated devices are physically present within the classroom network. The teacher device stores
verified records locally in an encrypted database and may later synchronize them to an online database
once connectivity becomes available. This design ensures data privacy, proxy-resistance, and
235 operational reliability even in offline conditions.
9
Figure 1 depicts the overall process flow of the offline Wi-Fi-based attendance system using mDNS
and fingerprint authentication. The flow begins when the teacher starts a session, generates a unique
240 classroom code, and advertises the session over the local Wi-Fi network using mDNS.
Simultaneously, a TCP server on the teacher device listens for incoming student connections.
Students enable airplane mode while keeping Wi-Fi active and connect to the same classroom
network. Their devices automatically discover the teacher’s session through mDNS advertisements.
Upon discovery, each student enters the classroom code displayed by the teacher. The system then
245 invokes mobile fingerprint authentication, ensuring that the individual attempting to mark attendance
is the legitimate student.
The teacher device verifies both the classroom code and fingerprint authentication result. If valid, the
attendance entry is recorded in real time on the teacher device; if invalid, the attempt is rejected and
250 logged. At the conclusion of the session, the teacher compiles an attendance report summarizing all
verified entries. When internet access becomes available, the report can be securely synchronized
with an institutional or cloud database. This workflow ensures seamless, tamper-resistant attendance
tracking entirely within a local Wi-Fi environment.
255 Figure 2 illustrates the detailed interaction between the system modules—TeacherApp,
mDNSService, TCPServer, StudentApp, and TCPClient—throughout an attendance session. The
process begins with the TeacherApp generating the classroom code and invoking the mDNSService
to advertise the session. The TCPServer is initialized to listen for client connections.
260 On the student side, the StudentApp ensures that the device is in airplane mode and connected to the
correct Wi-Fi network. The mDNSService running on the student device discovers the teacher’s
session and retrieves its IP and port. The TCPClient then connects to the teacher’s TCPServer. The
student application sends the classroom code and initiates fingerprint authentication. The fingerprint
verification generates a hashed biometric signature, which is combined with the session token and a
265 server-issued nonce to create an authentication token.
The teacher’s TCPServer validates the token by verifying the classroom code, registration number,
fingerprint hash, and network origin (based on BSSID and RSSI). If all checks are successful, the
attendance record is stored in the local database and a success acknowledgment is transmitted back
10
270 to the student device. Any mismatch such as an incorrect code, invalid fingerprint, or duplicated
device—results in an immediate rejection with an error message. The sequence concludes when the
teacher stops the session, generates a verified attendance report, and optionally uploads it for archival
once online connectivity resumes.
275 This interaction model demonstrates the real-time, multi-threaded communication and synchronous
validation architecture that differentiates the invention from existing cloud-dependent attendance
systems.
In one embodiment of the present invention, the authentication token used for verifying attendance
280 integrity is generated using a Hash-based Message Authentication Code (HMAC) algorithm. This
mechanism ensures that each attendance submission is uniquely bound to both the session instance
and the user’s fingerprint identity and cannot be replayed or forged.
When a student performs fingerprint authentication on the Student Application, the application
285 obtains a cryptographically secure fingerprint hash (FingerprintHash) from the mobile operating
system’s biometric API. The teacher’s device, upon advertising the session over the local Wi-Fi
network, generates a unique session token (SessionToken) at the start of every attendance session.
To link these two independent identifiers securely, the student device computes an authentication
token (AuthToken) using a symmetric secret key (AppSecretKey) that is pre-shared between the
290 teacher and student applications during installation. The computation follows the HMAC algorithm,
represented mathematically as:
AuthToken = HMAC(SessionToken ∥ FingerprintHash, AppSecretKey)
where
∥ denotes concatenation of the session token and fingerprint hash,
295 AppSecretKey is a cryptographic key embedded within the application’s secure enclave, and
HMAC() is a one-way keyed-hash function (e.g., SHA-256).
This operation ensures that any modification in either the fingerprint data or the session token
produces a completely different AuthToken, making spoofing or replay attacks computationally
infeasible. The teacher device receives this token through a secure TCP connection, verifies its
11
300 validity using the same secret key, and compares it against the active session token to confirm both
identity and proximity.
If the generated and received tokens match within the nonce-validity period (e.g., 10 seconds), the
student’s attendance is accepted and stored in the encrypted local database. Otherwise, the submission
is rejected, and an invalid-attempt log is recorded for audit purposes.
305 This cryptographic binding mechanism provides a tamper-proof, session-specific verification method
that enhances proxy prevention and ensures that biometric data never leaves the user’s device in raw
form, aligning with privacy and data protection standards.
Figure 3 (including sub-figures 3(a) – 3(e)) illustrates the graphical user interface of the Teacher
310 Application used to control and monitor attendance sessions. The login interface enables secure
authentication for authorized faculty members. After logging in, the teacher is presented with a class
list screen showing current and scheduled sessions, along with their statuses (e.g., “Locked,”
“Editable,” or “Completed”).
315 The teacher can initiate a new session by selecting a class, generating a session code, and releasing
attendance to students. The Release Attendance screen displays session metadata such as course code,
slot number, and number of enrolled students. The system automatically begins broadcasting session
details over the classroom Wi-Fi using mDNS, enabling nearby student devices to detect the session.
A countdown timer confirms the active attendance window, during which the teacher’s device accepts
320 and validates fingerprint-verified submissions.
After the session ends, the teacher interface displays summary statistics including total students,
number of presentees, and absentees. The teacher can review or edit the absentee list if necessary and
then lock and close the session. All data are stored locally in encrypted form, ensuring offline integrity
325 and secure post-session synchronization. The teacher application thus provides a complete control
panel for session creation, broadcast, validation monitoring, and report generation within a single,
internet-independent environment.
Figure 4 demonstrates the graphical user interface of the Student Application, which operates as the
330 client side of the proposed system. The initial login screen allows students to securely authenticate to
12
their local account. Upon login, the application displays the dashboard listing upcoming and
completed classes, dynamically populated once the device connects to the local Wi-Fi network and
detects mDNS advertisements from the teacher device.
335 When an attendance session is active, the student selects the corresponding class, enters the six-digit
classroom code shown by the teacher, and initiates fingerprint verification using the device’s
biometric sensor. The system generates a fingerprint hash and binds it with the session token through
the HMAC-based cryptographic process. The resulting authentication token is transmitted over a
local TCP connection to the teacher device for validation.
340
If authentication is successful, the application displays confirmation of attendance; otherwise, it
notifies the user of any mismatch or invalid submission. The interface thereby enables automatic
session discovery, secure offline verification, and immediate acknowledgment to the student,
ensuring a smooth and fraud-resistant attendance experience.
345
EXPERIMENTAL VALIDATION RESULTS
The following experimental validation was conducted to verify the functional performance,
reliability, and security of the proposed offline Wi-Fi-based attendance system using mDNS and
350 fingerprint authentication. The prototype was implemented as a pair of Android applications — a
Teacher App (server) and a Student App (client) — and evaluated in a controlled classroom
environment.
Experimental Setup
355
Parameter Description
Teacher Device Android smartphone (Qualcomm Snapdragon 732G, 6 GB RAM)
running Android 12
Student Devices 10 Android smartphones (Mi, Samsung, OnePlus models) running
Android 10–13
Network Environment Common classroom Wi-Fi access point (no internet connectivity)
Communication
Protocols
mDNS (UDP port 5353) for service discovery, TCP (port 4000–
8000) for data transfer
Authentication Mobile fingerprint authentication (Android Biometric API)
13
Language/Framework Java (Android SDK 30), SQLite (local database), AES-256 for
encryption
Test Users 1 teacher, 10 students per session (5 repeated trials)
Test Scenarios and Observed Results
The prototype system was evaluated under multiple operating conditions to validate discovery speed,
authentication reliability, and data integrity.
360
Test Scenario Objective Expected
Output
Observed Output Status
1. Session
Discovery & Join
Verify that students can
automatically detect
teacher’s session via
mDNS
Students discover
session within 5
seconds
All 10 devices
discovered session
within 3–4 seconds
Passed
2. Concurrent
Connections
Test multiple
simultaneous student
connections
Server handles
≥5 concurrent
connections
All 10 connected
successfully, stable
performance
Passed
3. Airplane Mode
Enforcement
Prevent external or offnetwork connections
Devices outside
classroom
network rejected
All off-network
devices rejected
automatically
Passed
4. Fingerprint
Authentication
Validate attendance
only after fingerprint
match
Attendance
recorded only for
verified users
All valid
fingerprints
accepted; duplicates
rejected
Passed
5. Real-Time
Attendance
Recording
Confirm immediate
logging after
verification
Record stored
instantly on
teacher device
All valid entries
logged within 1–2
seconds
Passed
Performance Metrics
Parameter Average Observed
Value
Remarks
Session discovery latency 2.9 seconds Time from mDNS advertisement to
detection
Fingerprint verification time 1.5 seconds Local biometric + nonce signing
End-to-end attendance
completion
~4.4 seconds Discovery → Authentication →
Logging
Successful verifications (inroom)
100% All legitimate users verified
successfully
Rejection of off-network
devices
100% None of the external devices
connected
Fingerprint False Reject Rate
(FRR)
2% Re-scan required in few attempts
14
Fingerprint False Accept Rate
(FAR)
0.4% No unauthorized attendance recorded
Network packet failure <1% Retransmitted automatically (TCP
retry)
CPU usage (teacher device) <40% Stable under 10 concurrent clients
Memory usage <180 MB Moderate; no leaks observed
Quantitative Technical Comparison
System Type Internet
Needed
Avg. Time
per
Record
Proxy
Prevention
Efficiency
Offline
Operation
Remarks
Conventional Wi-Fi
Attendance (manual
IP)
Yes 10–12 s 65% No Manual entry;
spoof-prone
Biometric + Cloud
Sync System
Yes 8 s 78% No Requires
central server
Smart Attend
(Proposed System)
No ≈ 4 s 95–98% Yes Fully offline,
secure mDNS
discovery
365
To ensure replay prevention and user authenticity, each attendance event used a cryptographically
bound token, computed as:
AuthToken = HMAC(SessionToken ∥ FingerprintHash, AppSecretKey)
Each token was validated on the teacher device against the active session token and nonce within a
370 10-second window. All invalid or duplicate tokens were rejected. The success rate for legitimate
tokens was 100%, confirming the reliability of the HMAC-based mechanism.
The present invention offers several significant advantages over conventional attendance systems,
particularly in terms of connectivity independence, reliability, security, and operational efficiency.
375 One of the primary advantages is that the system functions entirely in an offline mode within a local
Wi-Fi network, eliminating the dependency on internet connectivity or centralized cloud servers. This
ensures continuous usability in classrooms, offices, or remote environments where network
availability is limited. Another advantage of the invention is the use of multicast DNS (mDNS) for
zero-configuration service discovery, allowing student devices to automatically identify and connect
380 to the teacher’s session without requiring manual IP entry or network configuration. This feature
simplifies deployment, minimizes setup time, and enhances scalability for larger groups.
15
A further advantage lies in the integration of mobile fingerprint authentication with cryptographically
bound session verification, providing strong protection against proxy or fraudulent attendance. Unlike
traditional systems that merely log network presence, the proposed invention binds each biometric
385 event with a session token through an HMAC-based signature, ensuring that attendance can be
recorded only by a legitimate, physically present user. Additionally, the system achieves low-latency
real-time operation, with attendance validation and recording completed within approximately five
seconds, even when multiple users connect simultaneously. This responsiveness significantly
improves efficiency during large classroom sessions.
390
The invention also ensures data security and privacy by performing all fingerprint processing locally
on the user’s device and transmitting only encrypted authentication tokens to the teacher’s device.
Attendance records are stored in an encrypted local database on the teacher’s device, which can be
securely synchronized with institutional or cloud databases once internet connectivity becomes
395 available. This dual-layer storage mechanism maintains data integrity while providing flexibility in
record management.
Another technical advantage is the reduction of communication overhead and network congestion.
By employing lightweight TCP transactions limited to session tokens and verification responses, the
400 system reduces network data transfer by approximately one-third compared to conventional Wi-Fi or
cloud-based attendance mechanisms. The system also demonstrates enhanced proxy-prevention
accuracy, achieving between 95 and 98 percent reliability, and improves overall operational
throughput by reducing redundant handshakes and external server calls.
405 From a practical perspective, the invention is hardware-independent and cost-effective, operating
entirely on commercially available smartphones without requiring additional biometric scanners or
dedicated servers. This makes it highly suitable for educational institutions, organizations, and
enterprises seeking a secure, scalable, and easy-to-deploy attendance solution. The combination of
offline operation, secure mDNS discovery, fingerprint-bound authentication, and encrypted local
410 storage provides a robust, tamper-proof framework that ensures both operational simplicity and
technological advancement beyond existing system
16
CLAIMS:
WE CLAIM:
415 1. A system (100) for offline Wi-Fi-based attendance using mDNS and fingerprint
authentication, comprising:
a teacher device configured to initiate an attendance session and generate a unique session
identifier and classroom code;
an mDNS broadcast module on the teacher device configured to advertise said session
420 identifier over a local Wi-Fi network using multicast DNS so as to enable zeroconfiguration service discovery by client devices;
a TCP communication server running on the teacher device for establishing secure local
connections with multiple student devices without internet dependency;
a plurality of student devices configured to automatically discover the teacher device's
425 session via the mDNS advertisement and to connect thereto through a local TCP client;
an authentication module executed on each student device for capturing a user's biometric
fingerprint via a mobile fingerprint sensor and generating a fingerprint hash; and
a verification engine on the teacher device configured to validate each attendance
submission by verifying a cryptographically signed authentication token that binds the
430 session identifier with the fingerprint hash to confirm the student's identity and local
presence,
wherein attendance records are stored locally on the teacher device and optionally
synchronized to a remote database upon availability of internet connectivity.
2. The system (100) as claimed in claim 1, wherein the authentication token is computed
435 using a Hash-based Message Authentication Code (HMAC) of a concatenation of the
session token and fingerprint hash with an application secret key, expressed as
17
AuthToken = HMAC(SessionToken ‚à• FingerprintHash, AppSecretKey).
3. The system(100) as claimed in claim 1, wherein a nonce value generated by the teacher
device is included in the authentication token and validated for freshness within a pre440 defined expiry interval to prevent replay attacks.
4. The system(100) as claimed in claim1, wherein each student device is required to operate
in airplane mode with Wi-Fi enabled, so that communication occurs only within the local
Wi-Fi network and attendance requests originating outside the network are automatically
rejected.
445 5. The system(100) as claimed in claim1, wherein the teacher device records each verified
attendance entry with a timestamp, session identifier, and device identifier and stores said
entries in an encrypted local database.
6. The system(100) as claimed in claim1, wherein the mDNS advertisement is performed
using Android Network Service Discovery (NSD) API or equivalent library and is limited
450 to the local subnet so as to ensure physical proximity of clients.
7. The system(100) as claimed in claim1 , wherein the system is configured to compute a
local signal strength (RSSI) and Basic Service Set Identifier (BSSID) of connected devices
to verify physical presence within the classroom range.
8. The system(100) as claimed in claim1, wherein the attendance data is secured by AES455 based encryption before storage and only authorized users can access or export attendance
reports.
9. A method for offline Wi-Fi-based attendance using mDNS and fingerprint authentication,
comprising the steps of:
a) initiating an attendance session by a teacher device and generating a unique
460 session token and classroom code;
b) broadcasting said session token over a local Wi-Fi network via mDNS so that
student devices discover the session automatically;
c) connecting, by each student device, to the teacher device through a local TCP
client-server connection;
465 d) performing biometric fingerprint authentication on each student device and
computing a fingerprint hash;
18
e) generating an authentication token that combines the session token and
fingerprint hash and signing the token using a secret key;
f) transmitting the authentication token and classroom code to the teacher device
470 for verification;
g) verifying, by the teacher device, the validity of the authentication token and
ensuring that the request originates from within the local network; and
h) recording the attendance entry locally upon successful verification and
optionally synchronizing the data to a remote database when internet
475 connectivity is available.
Dated this 22nd day of November 2025
19
ABSTRACT
480 A SYSTEM AND METHOD FOR OFFLINE WI-FI-BASED ATTENDANCE USING MDNS
AND FINGERPRINT AUTHENTICATION
The present invention relates to a system(100) and method for offline Wi-Fi-based attendance using
multicast DNS (mDNS) and fingerprint authentication. The invention provides a secure, real-time,
485 and internet-independent attendance management framework in which a teacher device functions as
a local server that generates a unique session identifier and advertises it over a Wi-Fi network using
mDNS. Student devices automatically discover the session, connect through a local TCP channel,
and verify attendance through mobile fingerprint authentication. Each attendance submission is
validated using a cryptographically signed token generated as HMAC(SessionToken ∥
490 FingerprintHash, AppSecretKey), ensuring authenticity and preventing proxy or remote attendance.
Attendance data is stored locally in an encrypted database and can be synchronized to an online server
when connectivity becomes available. The system ensures rapid, tamper-proof, and privacypreserving attendance verification without requiring dedicated hardware or continuous internet
connectivity
495 Fig. 1
Dated this 22nd day of November 2025