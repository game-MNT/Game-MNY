# Game-MNT
information and culture 
  <script src="https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/9.23.0/firebase-auth-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/9.23.0/firebase-firestore-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/9.23.0/firebase-storage-compat.js"></script>

  <script>
    /* ------------------------------------------------------------------ */
    /* ====== 1. Firebase config (Үүнийг өөрийн төслийн мэдээллээр солино) ====== */
    /* ------------------------------------------------------------------ */
    const firebaseConfig = {
      apiKey: "YOUR_API_KEY", // Солих
      authDomain: "YOUR_PROJECT.firebaseapp.com", // Солих
      projectId: "YOUR_PROJECT", // Солих
      storageBucket: "YOUR_PROJECT.appspot.com", // Солих
      messagingSenderId: "SENDER_ID",
      appId: "APP_ID"
    };
    firebase.initializeApp(firebaseConfig);
    const auth = firebase.auth();
    const db = firebase.firestore();
    const storage = firebase.storage();

    /* ------------------------------------------------------------------ */
    /* ====== 2. COMIC & Quiz Data (Sample) ====== */
    /* ------------------------------------------------------------------ */
    const COMIC = {
      title: "Сэцэн Хан — Комик",
      panels: [
        { id:1, img:"https://via.placeholder.com/1200x700?text=Panel+1", text:"Эхний панел: Түүх эхэлнэ...", requiredLevel:1 },
        { id:2, img:"https://via.placeholder.com/1200x700?text=Panel+2", text:"Хоёр дахь панел: Маргаан даамжирна...", requiredLevel:2 },
        { id:3, img:"https://via.placeholder.com/1200x700?text=Panel+3", text:"Гурван дахь панел: Шийдвэр ирнэ...", requiredLevel:3 }
      ],
      quizzes: {
        1: { q:"Эхний үйл явдал ямар жил болсон бэ?", options:["1206","1227","1235"], correct:0, xp:40 },
        2: { q:"Энэ үйл явдал дахь гол дүр хэн бэ?", options:["Сэцэн хан","Нэр үгүй баатар","Гэрийн эзэн"], correct:0, xp:60 },
        3: { q:"Түүхээс юу сурсан бэ?", options:["Зөв удирдлага","Хүч чадал","Тэр нь чухал биш"], correct:0, xp:100 }
      }
    };

    /* ------------------------------------------------------------------ */
    /* ====== 3. Level / XP logic ====== */
    /* ------------------------------------------------------------------ */
    function computeLevelFromXP(xp){ return Math.floor(xp/100)+1; }
    function xpForLevel(level){ return level*100; }

    /* ------------------------------------------------------------------ */
    /* ====== 4. UI Refs (HTML элементүүд) ====== */
    /* ------------------------------------------------------------------ */
    const btnShowLogin = document.getElementById('btnShowLogin');
    const loginModal = document.getElementById('loginModal');
    const cancelLogin = document.getElementById('cancelLogin');
    const doRegister = document.getElementById('doRegister');
    const doLogin = document.getElementById('doLogin');
    const inputEmail = document.getElementById('inputEmail');
    const inputPass = document.getElementById('inputPass');

    const authButtons = document.getElementById('authButtons');
    const userHeader = document.getElementById('userHeader');
    const hdrAvatar = document.getElementById('hdrAvatar');
    const hdrEmail = document.getElementById('hdrEmail');
    const hdrLevel = document.getElementById('hdrLevel');
    const hdrXP = document.getElementById('hdrXP');

    const uiLevel = document.getElementById('uiLevel');
    const uiXP = document.getElementById('uiXP');
    const xpFill = document.getElementById('xpFill');
    const xpForNextEl = document.getElementById('xpForNext');

    const panelImage = document.getElementById('panelImage');
    const panelText = document.getElementById('panelText');
    const prevPanelBtn = document.getElementById('prevPanel');
    const nextPanelBtn = document.getElementById('nextPanel');
    const openQuizBtn = document.getElementById('openQuiz');
    const btnLogout = document.getElementById('btnLogout');

    const leaderboardEl = document.getElementById('leaderboard');
    const progressDetails = document.getElementById('progressDetails');

    const quizModal = document.getElementById('quizModal');
    const quizTitle = document.getElementById('quizTitle');
    const quizQuestion = document.getElementById('quizQuestion');
    const quizOptions = document.getElementById('quizOptions');
    const quizFeedback = document.getElementById('quizFeedback');
    const closeQuizBtn = document.getElementById('closeQuizBtn');

    const adminUpload = document.getElementById('adminUpload');
    const fileInput = document.getElementById('fileInput');
    const panelIdInput = document.getElementById('panelIdInput');
    const uploadBtn = document.getElementById('uploadBtn');
    const uploadStatus = document.getElementById('uploadStatus');

    /* ------------------------------------------------------------------ */
    /* ====== 5. State & Variables ====== */
    /* ------------------------------------------------------------------ */
    let currentUser = null;
    let userDoc = null; // User data from Firestore
    let panelIndex = 0; // Current displayed panel index (0-based)
    let activeQuizPanelId = null; 
    let lbUnsub = null; // Leaderboard unsubscribe listener

    /* ------------------------------------------------------------------ */
    /* ====== 6. Core Functions (UI Update & Comic Navigation) ====== */
    /* ------------------------------------------------------------------ */
    
    /**
     * Хэрэглэгчийн мэдээлэл (XP, Level, Progress) -ийг UI-д шинэчлэх.
     */
    function refreshUI(){
      if(userDoc && currentUser){
        const xp = userDoc.xp || 0;
        const level = computeLevelFromXP(xp);
        const panelsUnlocked = userDoc.panelsUnlocked || 1;
        
        // XP/Level тооцоолол
        const xpForCurrentLevel = xpForLevel(level);
        const xpForPrevLevel = xpForLevel(level - 1);
        const xpInLevel = xp - xpForPrevLevel; // Одоогийн түвшинд цуглуулсан XP
        const xpNeededForNext = xpForCurrentLevel - xpForPrevLevel; // Дараагийн түвшинд шаардлагатай XP
        const percentage = (xpInLevel / xpNeededForNext) * 100;
        
        // Header
        hdrEmail.textContent = currentUser.email;
        hdrAvatar.textContent = currentUser.email[0].toUpperCase();
        hdrLevel.textContent = level;
        hdrXP.textContent = xp;

        // XP Bar
        uiLevel.textContent = level;
        uiXP.textContent = xpInLevel;
        xpForNextEl.textContent = xpNeededForNext;
        xpFill.style.width = `${percentage > 100 ? 100 : percentage}%`;

        // Progress Details
        progressDetails.innerHTML = `
          <p>Та **Level ${level}** байна. (**${xp} XP**)</p>
          <p>Одоогийн байдлаар та **${panelsUnlocked}** панел нээсэн байна.</p>
        `;
        
        // Set the current panel index to the last unlocked panel
        panelIndex = panelsUnlocked - 1; 
      } else {
        // Logged out state defaults
        uiLevel.textContent = 1;
        uiXP.textContent = 0;
        xpForNextEl.textContent = 100;
        xpFill.style.width = '0%';
        panelIndex = 0;
        progressDetails.textContent = 'Нэвтэрч орсны дараа дэлгэрэнгүй харагдана.';
      }
      
      // Update the displayed panel regardless of login state
      updateComicPanel();
    }

    /**
     * Комикын тухайн панелийг харуулах, түгжээг шалгах, товчлуурыг удирдах.
     */
    function updateComicPanel(){
      const panel = COMIC.panels[panelIndex];
      if (!panel) return;

      const userLevel = userDoc ? computeLevelFromXP(userDoc.xp || 0) : 1;
      const panelsUnlocked = userDoc ? userDoc.panelsUnlocked || 1 : 1;
      const isLocked = !currentUser || panelIndex >= panelsUnlocked; // Панел нээгдсэн эсэх

      // Update image and text
      panelImage.src = panel.img;
      
      // Apply/Remove locked state class
      if (isLocked) {
        panelImage.classList.add('locked');
        openQuizBtn.disabled = true;
        panelText.textContent = `Панел ${panel.id} - Түгжигдсэн. (Шаардлагатай Level: ${panel.requiredLevel})`;
      } else {
        panelImage.classList.remove('locked');
        panelText.textContent = panel.text;
        
        // Quiz is only available on the LAST read panel for that user
        openQuizBtn.disabled = panel.id !== panelsUnlocked;
      }

      // Handle navigation buttons (Prev/Next)
      prevPanelBtn.disabled = panelIndex === 0;
      // Хэрэглэгчийн нээсэн панел дотор л навигац хийнэ.
      nextPanelBtn.disabled = panelIndex >= panelsUnlocked - 1 || panelIndex === COMIC.panels.length - 1; 
    }

    prevPanelBtn.onclick = () => {
      if (panelIndex > 0) {
        panelIndex--;
        updateComicPanel();
      }
    };

    nextPanelBtn.onclick = () => {
      if (panelIndex < COMIC.panels.length - 1) {
        panelIndex++;
        updateComicPanel();
      }
    };

    /* ------------------------------------------------------------------ */
    /* ====== 7. Quiz Logic ====== */
    /* ------------------------------------------------------------------ */
    
    openQuizBtn.onclick = () => {
        if (!currentUser) { alert('Нэвтэрнэ үү.'); return; }
        
        activeQuizPanelId = COMIC.panels[panelIndex].id;
        const quiz = COMIC.quizzes[activeQuizPanelId];

        if (!quiz) {
            alert('Энэ панелд асуулт байхгүй байна.');
            return;
        }

        quizTitle.textContent = `Асуулт: Панел ${activeQuizPanelId}`;
        quizQuestion.textContent = quiz.q;
        quizOptions.innerHTML = '';
        quizFeedback.textContent = '';
        
        quiz.options.forEach((option, index) => {
            const btn = document.createElement('button');
            btn.className = 'option';
            btn.textContent = option;
            btn.onclick = () => checkAnswer(activeQuizPanelId, index, quiz.correct, quiz.xp);
            quizOptions.appendChild(btn);
        });

        quizModal.style.display = 'flex';
    };

    closeQuizBtn.onclick = () => {
        quizModal.style.display = 'none';
        // Quiz button enabled by updateComicPanel() when user lands on quiz panel
    };
    
    function checkAnswer(panelId, selectedIndex, correctIndex, xpReward) {
        // Disable options after selection
        quizOptions.querySelectorAll('.option').forEach(btn => btn.disabled = true);
        
        if (selectedIndex === correctIndex) {
            quizFeedback.className = 'feedback success';
            quizFeedback.innerHTML = `🎉 Зөв хариулт! Та **${xpReward} XP** авлаа.`;
            
            // Update User Document in Firestore
            db.collection('users').doc(currentUser.uid).update({
                xp: firebase.firestore.FieldValue.increment(xpReward),
                panelsUnlocked: firebase.firestore.FieldValue.increment(1) // Unlock the next panel
            }).then(() => {
                // UI will refresh automatically via onSnapshot listener
                setTimeout(() => {
                    quizModal.style.display = 'none';
                    // Move to the newly unlocked panel
                    if(panelId < COMIC.panels.length) { 
                        panelIndex = panelId; // panelId is 1-based, index is 0-based
                        updateComicPanel();
                    }
                }, 1500);
            }).catch(e => {
                quizFeedback.innerHTML += `<br>Алдаа гарлаа: ${e.message}`;
            });

        } else {
            quizFeedback.className = 'feedback fail';
            quizFeedback.innerHTML = `❌ Буруу хариулт. Зөв хариулт нь: **${COMIC.quizzes[panelId].options[correctIndex]}**. Дахин оролдож болно.`;
            // Re-enable options for another try
            setTimeout(() => {
                quizOptions.querySelectorAll('.option').forEach(btn => btn.disabled = false);
            }, 1000);
        }
    }

    /* ------------------------------------------------------------------ */
    /* ====== 8. Leaderboard Logic ====== */
    /* ------------------------------------------------------------------ */
    function startLeaderboard() {
      if(lbUnsub) stopLeaderboard();
      lbUnsub = db.collection('users').orderBy('xp', 'desc').limit(10).onSnapshot(snapshot => {
        leaderboardEl.innerHTML = '';
        snapshot.forEach((doc, index) => {
          const data = doc.data();
          const level = computeLevelFromXP(data.xp || 0);
          const rank = index + 1;
          leaderboardEl.innerHTML += `
            <li>
              <div class="profile">
                <div class="avatar small" style="width:30px;height:30px;font-size:12px">${data.email[0].toUpperCase()}</div>
                <div>
                  <div style="font-weight:600">${rank}. ${data.email.split('@')[0]}</div>
                  <div class="meta">Level ${level}</div>
                </div>
              </div>
              <div style="font-weight:700;color:var(--primary)">${data.xp || 0} XP</div>
            </li>
          `;
        });
      });
    }

    function stopLeaderboard() {
        if(lbUnsub) lbUnsub();
        leaderboardEl.innerHTML = '';
        lbUnsub = null;
    }
    
    /* ------------------------------------------------------------------ */
    /* ====== 9. Admin Logic ====== */
    /* ------------------------------------------------------------------ */
    const ADMIN_EMAIL = 'admin@admin.com'; 
    
    function maybeShowAdmin() {
        if (currentUser && currentUser.email === ADMIN_EMAIL) {
            adminUpload.hidden = false;
        } else {
            adminUpload.hidden = true;
        }
    }

    uploadBtn.onclick = () => {
        const file = fileInput.files[0];
        const panelId = panelIdInput.value;
        if (!file || !panelId) {
            uploadStatus.textContent = 'Файл болон Panel ID-г оруулна уу.';
            return;
        }
        
        uploadStatus.textContent = 'Зураг upload хийж байна...';
        const storageRef = storage.ref(`comic_panels/panel_${panelId}_${file.name}`);
        
        storageRef.put(file).then(snapshot => {
            return snapshot.ref.getDownloadURL();
        }).then(url => {
            uploadStatus.textContent = `Амжилттай upload хийлээ. URL: ${url}`;
        }).catch(e => {
            uploadStatus.textContent = `Upload хийхэд алдаа гарлаа: ${e.message}`;
        });
    };

    /* ------------------------------------------------------------------ */
    /* ====== 10. Auth Listeners & UI Bindings ====== */
    /* ------------------------------------------------------------------ */
    
    // Auth UI Handlers
    btnShowLogin.onclick = ()=>{ loginModal.style.display='flex'; }
    cancelLogin.onclick = ()=>{ loginModal.style.display='none'; inputEmail.value=''; inputPass.value=''; }

    doRegister.onclick = ()=>{
      const email=inputEmail.value.trim(), pass=inputPass.value.trim();
      if(!email||!pass){ alert('Имэйл болон нууц үг оруулна уу'); return; }
      auth.createUserWithEmailAndPassword(email,pass).then(cred=>{
        // New user starts at 0 XP and panelsUnlocked: 1 (the first panel)
        return db.collection('users').doc(cred.user.uid).set({email,xp:0,panelsUnlocked:1});
      }).then(()=>{ loginModal.style.display='none'; inputEmail.value=''; inputPass.value=''; }).catch(e=>alert(e.message));
    };
    doLogin.onclick = ()=>{
      const email=inputEmail.value.trim(), pass=inputPass.value.trim();
      if(!email||!pass){ alert('Имэйл болон нууц үг оруулна уу'); return; }
      auth.signInWithEmailAndPassword(email,pass).then(()=>{ loginModal.style.display='none'; inputEmail.value=''; inputPass.value=''; }).catch(e=>alert(e.message));
    };
    btnLogout.onclick = ()=> auth.signOut();
    
    // Main Auth State Observer
    auth.onAuthStateChanged(u=>{
      currentUser=u;
      if(u){
        authButtons.style.display='none';
        userHeader.style.display='flex';
        btnLogout.style.display='';
        
        // Listen to user's data (XP/Level/Progress) in real-time
        db.collection('users').doc(u.uid).onSnapshot(doc=>{
            userDoc=doc.exists?doc.data():null; 
            refreshUI();
        });
        startLeaderboard();
        maybeShowAdmin();
      }else{
        authButtons.style.display='';
        userHeader.style.display='none';
        btnLogout.style.display='none';
        userDoc=null;
        stopLeaderboard();
        maybeShowAdmin(); // Hide admin panel on logout
        refreshUI();
      }
    });

  </script>
