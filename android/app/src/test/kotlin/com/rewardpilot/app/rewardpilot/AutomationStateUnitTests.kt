package com.rewardpilot.app.rewardpilot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomationStateUnitTests {

    @Test
    fun testPackageTargetIsCoinMaster() {
        assertEquals("com.moonactive.coinmaster", CoinMasterAccessibilityService.COIN_MASTER_PACKAGE)
    }

    @Test
    fun testForceStopFlagLifecycle() {
        val flag = CoinMasterAccessibilityService.isForceStopped
        flag.set(false)
        assertFalse(flag.get())

        // Emergency trigger
        flag.set(true)
        assertTrue(flag.get())

        // Reset
        flag.set(false)
        assertFalse(flag.get())
    }

    @Test
    fun testRewardButtonPatterns() {
        val collectKeywords = listOf("Collect", "COLLECT", "Collect Now", "Claim", "CLAIM", "Get Spins")
        val dismissKeywords = listOf("OK", "Ok", "ok", "Close", "CLOSE", "Continue")

        for (kw in collectKeywords) {
            val lower = kw.lowercase()
            assertTrue(lower.contains("collect") || lower.contains("claim") || lower.contains("get spins"))
        }

        for (kw in dismissKeywords) {
            val lower = kw.lowercase()
            assertTrue(lower.contains("ok") || lower.contains("close") || lower.contains("continue"))
        }
    }
}
