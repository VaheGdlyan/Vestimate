# 🧥 Vestimate

Vestimate is a high-end personal AI styling application that helps users digitize their wardrobes, get weather-appropriate outfit recommendations, and interact with a premium AI Stylist. Leveraging computer vision for instant garment categorization and advanced conversational AI for personalized fashion advice, it delivers a state-of-the-art closet management experience.

---

## 🚀 How to Run Locally (Local Development Server)

Follow these exact commands to launch the Backend Engine and Frontend Client side-by-side in your terminal of choice.

### **Option A: Using Git Bash (Recommended)**

#### **1. Start the Backend Engine:**
Open a Git Bash terminal at the project root and run:
```bash
cd "/c/Users/User/OneDrive/Рабочий стол/Projects/Vestimate"
./venv/Scripts/python vestimate/main.py
```

#### **2. Start the Frontend App:**
Open a second Git Bash terminal and run:
```bash
export PATH="$PATH:/c/flutter/bin:/c/Program Files/Git/cmd"
cd "/c/Users/User/OneDrive/Рабочий стол/Projects/Vestimate/vestimate/mobile"
flutter run -d chrome
```

---

### **Option B: Using Windows PowerShell**

#### **1. Start the Backend Engine:**
Open a PowerShell window at the project root and run:
```powershell
cd "c:\Users\User\OneDrive\Рабочий стол\Projects\Vestimate"
.\venv\Scripts\python.exe vestimate/main.py
```

#### **2. Start the Frontend App:**
Open a second PowerShell window and run:
```powershell
$env:Path += ";C:\flutter\bin;C:\Program Files\Git\cmd"
cd "c:\Users\User\OneDrive\Рабочий стол\Projects\Vestimate\vestimate\mobile"
flutter run -d chrome
```

---

## 🎨 Key Features Demonstrated
- **Weather-Aware Recommendations:** Outfit selector automatically queries the local weather API to propose the perfect look.
- **Smart Upload & Classification:** Local demo classification automatically maps uploaded items to core categories (`tops`, `bottoms`, `outerwear`).
- **Premium AI Stylist:** A conversational partner loaded with high-fashion expertise and smart fallback capabilities.
- **Outfit History Gallery:** Persisted log of saved combinations displayed directly inside the user profile and history tab.
